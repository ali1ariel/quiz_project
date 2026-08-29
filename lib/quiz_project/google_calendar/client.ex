defmodule QuizProject.GoogleCalendar.Client do
  @moduledoc """
  Chamadas autenticadas à API do Google (Calendar v3 e OAuth2 userinfo).

  Recebe sempre um access token já válido — quem garante isso é
  `QuizProject.GoogleCalendar.OAuth.get_valid_access_token/1`, chamado pelo
  contexto antes de cada operação.
  """

  require Logger

  @calendar_base "https://www.googleapis.com/calendar/v3"
  @userinfo_url "https://www.googleapis.com/oauth2/v2/userinfo"

  @doc "Busca o e-mail da conta Google autenticada."
  def get_userinfo(access_token) do
    case get(@userinfo_url, access_token) do
      {:ok, %{"email" => email}} -> {:ok, email}
      {:ok, body} -> {:error, {:unexpected_response, body}}
      error -> error
    end
  end

  @doc "Cria o calendário secundário dedicado do usuário e devolve seu id."
  def create_calendar(access_token, summary) do
    case post("#{@calendar_base}/calendars", access_token, %{summary: summary}) do
      {:ok, %{"id" => calendar_id}} -> {:ok, calendar_id}
      {:ok, body} -> {:error, {:unexpected_response, body}}
      error -> error
    end
  end

  @doc "Cria um evento no calendário dedicado. Devolve o evento completo (id, updated, ...)."
  def insert_event(access_token, calendar_id, event_body) do
    post(events_url(calendar_id), access_token, event_body)
  end

  @doc "Atualiza (parcialmente) um evento existente no calendário dedicado."
  def patch_event(access_token, calendar_id, event_id, event_body) do
    url = events_url(calendar_id) <> "/" <> URI.encode_www_form(event_id)
    request(:patch, url, access_token, event_body)
  end

  defp events_url(calendar_id) do
    "#{@calendar_base}/calendars/#{URI.encode_www_form(calendar_id)}/events"
  end

  defp get(url, access_token), do: request(:get, url, access_token, nil)
  defp post(url, access_token, json), do: request(:post, url, access_token, json)

  defp request(method, url, access_token, json) do
    opts =
      [method: method, url: url, headers: [{"authorization", "Bearer #{access_token}"}]]
      |> maybe_put_json(json)
      |> Keyword.put(:receive_timeout, 10_000)
      |> Kernel.++(Application.get_env(:quiz_project, :google_req_options, []))

    case Req.request(Req.new(opts)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[GoogleCalendar.Client] Erro HTTP #{status} do Google: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("[GoogleCalendar.Client] Erro de conexão com o Google: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, json), do: Keyword.put(opts, :json, json)
end
