defmodule QuizProject.GoogleCalendar do
  @moduledoc """
  Sincronização de Prioridades com o Google Calendar: cada usuário conecta
  sua própria conta via OAuth2 e ganha um calendário secundário dedicado
  ("QuizProject — Atividades"), onde as atividades são espelhadas como
  eventos de dia inteiro. Este módulo orquestra `GoogleCalendar.OAuth`
  (autenticação) e `GoogleCalendar.Client` (chamadas à API), persistindo o
  estado da conexão via `QuizProject.Accounts` e o vínculo de cada atividade
  via `QuizProject.Priorities` — do mesmo jeito que `Priorities` já chama
  `AdaptiveStudy`/`Attempts` hoje.
  """

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar.{Client, OAuth}
  alias QuizProject.Priorities

  @calendar_summary "QuizProject — Atividades"

  @doc "URL de consentimento do Google para iniciar a conexão."
  defdelegate authorize_url(state), to: OAuth

  @doc """
  Troca o código de autorização por tokens, cria o calendário dedicado e
  grava a conexão do usuário — substituindo uma conexão anterior, se
  existir (reconexão). Em seguida, dispara em background o backfill das
  atividades pendentes já existentes (sem isso, o calendário nasceria vazio
  até a próxima mutação de cada uma).
  """
  def connect(user, code) do
    with {:ok, token_data} <- OAuth.exchange_code(code),
         {:ok, email} <- Client.get_userinfo(token_data.access_token),
         {:ok, calendar_id} <- Client.create_calendar(token_data.access_token, @calendar_summary),
         {:ok, connection} <-
           Accounts.upsert_google_calendar_connection(user, %{
             google_account_email: email,
             access_token: token_data.access_token,
             refresh_token: token_data.refresh_token,
             access_token_expires_at: token_data.expires_at,
             calendar_id: calendar_id
           }) do
      backfill(user)
      {:ok, connection}
    end
  end

  @doc """
  Desconecta o usuário do Google Calendar — revoga o token no Google
  (melhor esforço) e apaga a conexão salva. Não apaga o calendário nem os
  eventos do lado do Google: só para de sincronizar.
  """
  def disconnect(user) do
    with {:ok, connection} <- Accounts.get_google_calendar_connection(user) do
      OAuth.revoke(connection.refresh_token)
      Accounts.disconnect_google_calendar(connection, user)
    end
  end

  @doc """
  Sincroniza a criação de uma atividade pro Google Calendar (evento novo).
  Chamado por `Priorities.create_activity/2` via `QuizProject.Jobs.run/1` —
  sem conexão do usuário, não faz nada (é o gate de toda sincronização de
  saída).
  """
  def sync_out_create(activity), do: sync_out(activity, :insert)

  @doc """
  Sincroniza uma atualização de atividade (título, status, adiamento, ...)
  pro Google Calendar. Se a atividade ainda não tem evento vinculado (ex.:
  foi criada antes do usuário conectar o Google), cria o evento agora em
  vez de tentar um patch sem o que atualizar.
  """
  def sync_out_update(activity), do: sync_out(activity, :patch)

  # Recarrega a atividade em vez de confiar no `google_event_id` da struct
  # que o chamador passou: `Jobs.run/1` é fire-and-forget, então uma
  # mutação seguinte pode chegar aqui antes (ou pouco depois, mas ainda com
  # a cópia antiga em memória) do vínculo do evento anterior ser gravado —
  # decidir insert-vs-patch com um valor desatualizado criaria um evento
  # duplicado no Google em vez de atualizar o existente.
  defp sync_out(%{id: activity_id, user_id: user_id}, kind) do
    with {:ok, connection} <- Accounts.get_google_calendar_connection(%{id: user_id}),
         {:ok, access_token} <- OAuth.get_valid_access_token(connection),
         {:ok, activity} <- Priorities.get_activity(activity_id, %{id: user_id}) do
      do_sync_out(activity, connection, access_token, kind)
    else
      {:error, :not_found} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp do_sync_out(%{google_event_id: nil} = activity, connection, access_token, _kind) do
    upsert_event(activity, connection, access_token, &Client.insert_event/3)
  end

  defp do_sync_out(activity, connection, access_token, :patch) do
    upsert_event(activity, connection, access_token, fn access_token, calendar_id, body ->
      Client.patch_event(access_token, calendar_id, activity.google_event_id, body)
    end)
  end

  defp upsert_event(activity, connection, access_token, call) do
    case call.(access_token, connection.calendar_id, event_body(activity)) do
      {:ok, %{"id" => google_event_id} = event} ->
        Priorities.link_google_event(activity, google_event_id, parse_updated(event))

      {:error, _reason} = error ->
        error
    end
  end

  defp backfill(user) do
    QuizProject.Jobs.run(fn ->
      user
      |> Priorities.list_pending_activities_from(QuizProject.Priorities.Clock.today())
      |> Enum.each(&sync_out_create/1)
    end)
  end

  defp event_body(activity) do
    base = %{
      summary: activity.title,
      description: activity.notes,
      start: %{date: Date.to_iso8601(activity.logical_date)},
      end: %{date: Date.to_iso8601(Date.add(activity.logical_date, 1))}
    }

    case color_id(activity) do
      nil -> base
      color_id -> Map.put(base, :colorId, color_id)
    end
  end

  # Google Calendar não tem noção de "concluída"/"adiada" — usamos a cor do
  # evento (campo próprio, não o título) pra dar esse sinal visual sem
  # precisar parsear nada de volta na sincronização de entrada.
  defp color_id(%{status: :concluida}), do: "10"
  defp color_id(%{status: :nao_cumprida}), do: "11"
  defp color_id(%{status: :descartada}), do: "8"
  defp color_id(%{snoozed_until: snoozed}) when not is_nil(snoozed), do: "5"
  defp color_id(_activity), do: nil

  defp parse_updated(%{"updated" => updated}) do
    case DateTime.from_iso8601(updated) do
      {:ok, datetime, _offset} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_updated(_event), do: DateTime.utc_now()
end
