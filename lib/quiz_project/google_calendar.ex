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

  require Logger

  @calendar_summary "QuizProject — Atividades"
  # Bem abaixo do teto do Google (RFC diz até uns dias — na prática o canal
  # costuma durar menos do que o pedido); a renovação periódica
  # (`GoogleCalendar.WatchRenewer`) cuida de manter isso sempre coberto.
  @watch_ttl_ms 7 * 24 * 60 * 60 * 1000

  @doc "URL de consentimento do Google para iniciar a conexão."
  defdelegate authorize_url(state), to: OAuth

  @doc """
  Troca o código de autorização por tokens, cria o calendário dedicado e
  grava a conexão do usuário — substituindo uma conexão anterior, se
  existir (reconexão). Em seguida registra o canal de push notifications
  (sync de entrada) e dispara em background o backfill das atividades
  pendentes já existentes (sem isso, o calendário nasceria vazio até a
  próxima mutação de cada uma). Falha ao registrar o watch não derruba a
  conexão — sem ele o app só perde o sync de entrada até a próxima
  renovação (`GoogleCalendar.WatchRenewer`), continua escrevendo pro
  Google normalmente.
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
      start_watching(connection)
      backfill(user)
      {:ok, connection}
    end
  end

  @doc """
  Desconecta o usuário do Google Calendar — revoga o token e encerra o
  canal de push notifications no Google (ambos melhor esforço) e apaga a
  conexão salva. Não apaga o calendário nem os eventos do lado do Google:
  só para de sincronizar.
  """
  def disconnect(user) do
    with {:ok, connection} <- Accounts.get_google_calendar_connection(user) do
      OAuth.revoke(connection.refresh_token)
      stop_existing_channel(connection)
      Accounts.disconnect_google_calendar(connection, user)
    end
  end

  @doc """
  Renova o canal de push notifications de uma conexão — encerra o canal
  antigo (melhor esforço) e registra um novo. Usado por
  `GoogleCalendar.WatchRenewer` antes do canal expirar; Google não renova
  sozinho, e sem isso o sync de entrada simplesmente para de funcionar
  silenciosamente depois de alguns dias.
  """
  def renew_watch_channel(connection) do
    stop_existing_channel(connection)
    start_watching(connection)
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

  defp sync_out(%{id: activity_id, user_id: user_id}, kind) do
    case Accounts.get_google_calendar_connection(%{id: user_id}) do
      {:error, :not_found} -> :ok
      {:ok, connection} -> sync_out_with_connection(connection, activity_id, user_id, kind)
    end
  end

  # Recarrega a atividade em vez de confiar no `google_event_id` da struct
  # que o chamador passou: `Jobs.run/1` é fire-and-forget, então uma
  # mutação seguinte pode chegar aqui antes (ou pouco depois, mas ainda com
  # a cópia antiga em memória) do vínculo do evento anterior ser gravado —
  # decidir insert-vs-patch com um valor desatualizado criaria um evento
  # duplicado no Google em vez de atualizar o existente.
  #
  # Qualquer falha aqui (token revogado, Google fora do ar, ...) fica
  # registrada em `last_sync_error` — sem isso o usuário não teria como
  # descobrir que a sincronização parou, já que tudo roda em background.
  defp sync_out_with_connection(connection, activity_id, user_id, kind) do
    with {:ok, access_token} <- OAuth.get_valid_access_token(connection),
         {:ok, activity} <- Priorities.get_activity(activity_id, %{id: user_id}),
         {:ok, _updated} = ok <- do_sync_out(activity, connection, access_token, kind) do
      ok
    else
      {:error, :not_found} ->
        :ok

      {:error, reason} = error ->
        Accounts.record_google_calendar_sync_error(connection, inspect(reason))
        error
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

  defp start_watching(connection) do
    with {:ok, access_token} <- OAuth.get_valid_access_token(connection) do
      channel_id = Ash.UUID.generate()
      channel_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
      expiration_ms = System.system_time(:millisecond) + @watch_ttl_ms

      with {:ok, watch} <-
             Client.watch_events(
               access_token,
               connection.calendar_id,
               channel_id,
               channel_token,
               webhook_url(),
               expiration_ms
             ),
           {:ok, updated_connection} <-
             Accounts.update_google_calendar_watch_channel(connection, %{
               channel_id: channel_id,
               channel_token_hash: hash_channel_token(channel_token),
               channel_resource_id: watch["resourceId"],
               channel_expires_at: parse_expiration(watch["expiration"])
             }) do
        capture_baseline_sync_token(updated_connection, access_token)
      else
        {:error, reason} ->
          Logger.warning("[GoogleCalendar] Falha ao registrar watch channel: #{inspect(reason)}")
          Accounts.record_google_calendar_sync_error(connection, inspect(reason))
      end
    end
  end

  defp stop_existing_channel(%{channel_id: nil}), do: :ok

  defp stop_existing_channel(connection) do
    with {:ok, access_token} <- OAuth.get_valid_access_token(connection) do
      Client.stop_channel(access_token, connection.channel_id, connection.channel_resource_id)
    end

    :ok
  end

  defp capture_baseline_sync_token(connection, access_token, page_token \\ nil) do
    query = if page_token, do: %{pageToken: page_token}, else: %{}

    case Client.list_events(access_token, connection.calendar_id, query) do
      {:ok, %{"nextPageToken" => next_page_token}} ->
        capture_baseline_sync_token(connection, access_token, next_page_token)

      {:ok, %{"nextSyncToken" => sync_token}} ->
        Accounts.update_google_calendar_sync_state(connection, sync_token)

      {:error, reason} = error ->
        Logger.warning(
          "[GoogleCalendar] Falha ao capturar sync_token inicial: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Verifica o token do canal de push notifications de uma notificação do
  webhook contra o hash salvo na conexão (`X-Goog-Channel-Token`).
  """
  def verify_channel_token?(%{channel_token_hash: hash}, token)
      when is_binary(token) and is_binary(hash) do
    Plug.Crypto.secure_compare(hash_channel_token(token), hash)
  end

  def verify_channel_token?(_connection, _token), do: false

  @doc """
  Sincronização de entrada: busca no calendário dedicado os eventos
  alterados desde o último `sync_token` (ou lista tudo, se ainda não há
  um) e reconcilia cada um com a `Activity` correspondente. Chamado pelo
  webhook via `QuizProject.Jobs.run/1` — nunca bloqueia a requisição do
  Google, que só precisa saber que a notificação chegou.
  """
  def reconcile(connection) do
    with {:ok, access_token} <- OAuth.get_valid_access_token(connection) do
      list_and_reconcile(connection, access_token, connection.sync_token, nil)
    end
  end

  defp list_and_reconcile(connection, access_token, sync_token, page_token) do
    case Client.list_events(
           access_token,
           connection.calendar_id,
           sync_query(sync_token, page_token)
         ) do
      {:ok, %{"items" => items} = page} ->
        Enum.each(items, &reconcile_event(connection, &1))
        continue_or_finish(connection, access_token, sync_token, page)

      {:error, {:http_error, 410, _body}} ->
        # Google considera o sync_token velho demais pra continuar de onde
        # parou — só resta recomeçar do zero (listagem completa) e
        # recapturar um `nextSyncToken` novo no fim dela.
        Accounts.update_google_calendar_sync_state(connection, nil)
        list_and_reconcile(connection, access_token, nil, nil)

      {:error, reason} = error ->
        Accounts.record_google_calendar_sync_error(connection, inspect(reason))
        error
    end
  end

  defp sync_query(nil, nil), do: %{}
  defp sync_query(nil, page_token), do: %{pageToken: page_token}
  defp sync_query(sync_token, nil), do: %{syncToken: sync_token}
  defp sync_query(sync_token, page_token), do: %{syncToken: sync_token, pageToken: page_token}

  defp continue_or_finish(connection, access_token, sync_token, %{
         "nextPageToken" => next_page_token
       }) do
    list_and_reconcile(connection, access_token, sync_token, next_page_token)
  end

  defp continue_or_finish(connection, _access_token, _sync_token, %{
         "nextSyncToken" => next_sync_token
       }) do
    Accounts.update_google_calendar_sync_state(connection, next_sync_token)
  end

  defp reconcile_event(_connection, %{"id" => google_event_id, "status" => "cancelled"}) do
    case Priorities.get_activity_by_google_event_id(google_event_id) do
      {:ok, activity} -> Priorities.unlink_google_event(activity)
      {:error, :not_found} -> :ok
    end
  end

  defp reconcile_event(connection, %{"id" => google_event_id} = event) do
    case Priorities.get_activity_by_google_event_id(google_event_id) do
      {:ok, activity} -> apply_google_update(activity, event)
      {:error, :not_found} -> maybe_create_loose_capture(connection, event)
    end
  end

  # Um evento vivo sem `status`/`id` não é um evento de verdade — Google não
  # manda isso, mas não custa não estourar numa notificação inesperada.
  defp reconcile_event(_connection, _event), do: :ok

  defp apply_google_update(activity, event) do
    updated_at = parse_updated(event)

    if echo?(activity, updated_at) do
      :ok
    else
      case event_date(event) do
        {:ok, logical_date} ->
          Priorities.sync_activity_from_google(activity, %{
            title: Map.get(event, "summary", activity.title),
            notes: Map.get(event, "description"),
            logical_date: logical_date,
            google_updated_at: updated_at
          })

        :error ->
          :ok
      end
    end
  end

  # `event.updated` não muda mais cedo que a própria escrita de saída do
  # app — se não é mais novo que o que já temos salvo, é eco da nossa
  # última chamada `insert`/`patch`, não uma edição feita no Google.
  defp echo?(%{google_updated_at: nil}, _updated_at), do: false

  defp echo?(%{google_updated_at: known_updated_at}, updated_at) do
    DateTime.compare(updated_at, known_updated_at) != :gt
  end

  defp maybe_create_loose_capture(connection, event) do
    case event_date(event) do
      {:ok, logical_date} ->
        Priorities.create_activity_from_google(%{id: connection.user_id}, %{
          title: Map.get(event, "summary", "(sem título)"),
          notes: Map.get(event, "description"),
          logical_date: logical_date,
          google_event_id: event["id"],
          google_updated_at: parse_updated(event)
        })

      :error ->
        Logger.warning(
          "[GoogleCalendar] Evento novo com horário ignorado (sem conceito de horário no produto): #{event["id"]}"
        )

        :ok
    end
  end

  defp event_date(%{"start" => %{"date" => date}}) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _reason} -> :error
    end
  end

  defp event_date(_event), do: :error

  defp webhook_url, do: Application.fetch_env!(:quiz_project, :google_calendar_webhook_url)

  defp hash_channel_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp parse_expiration(nil), do: nil

  defp parse_expiration(ms) when is_binary(ms) do
    case Integer.parse(ms) do
      {int, _rest} -> DateTime.from_unix!(int, :millisecond)
      :error -> nil
    end
  end

  defp parse_expiration(ms) when is_integer(ms), do: DateTime.from_unix!(ms, :millisecond)

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
