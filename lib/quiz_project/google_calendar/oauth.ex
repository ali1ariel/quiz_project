defmodule QuizProject.GoogleCalendar.OAuth do
  @moduledoc """
  Autenticação OAuth2 com o Google para a sincronização de Google Calendar:
  URL de consentimento, troca de código por token, renovação do access
  token e revogação. Cliente HTTP é sempre `Req`, seguindo o padrão dos
  outros providers externos (ver `QuizProject.AI.Gemini`).

  Escopo pedido inclui `.../auth/calendar` (não o mais restrito
  `calendar.events`), porque a conexão inicial precisa de `calendars.insert`
  pra criar o calendário secundário dedicado do usuário, e
  `.../auth/userinfo.email`, porque `GoogleCalendar.Client.get_userinfo/1`
  chama o endpoint de userinfo pra mostrar qual conta está conectada em
  Configurações — sem esse segundo escopo o Google rejeita essa chamada com
  401 ("missing required authentication credential"), mesmo o token tendo
  acesso ao Calendar.
  """

  require Logger

  @scope "https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/userinfo.email"
  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @revoke_url "https://oauth2.googleapis.com/revoke"

  @doc "Monta a URL de consentimento do Google para o usuário conectar sua conta."
  def authorize_url(state) do
    query =
      URI.encode_query(%{
        client_id: client_id(),
        redirect_uri: redirect_uri(),
        response_type: "code",
        scope: @scope,
        access_type: "offline",
        # Força a tela de consentimento mesmo numa reconexão, pra garantir
        # que o Google sempre devolva um refresh_token novo — sem isso, uma
        # reconexão depois de desconectar poderia ficar sem refresh_token.
        prompt: "consent",
        state: state
      })

    @authorize_url <> "?" <> query
  end

  @doc "Troca o código de autorização por access/refresh token."
  def exchange_code(code) do
    post_token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri())
  end

  @doc "Renova o access token a partir do refresh token."
  def refresh_access_token(refresh_token) do
    post_token(grant_type: "refresh_token", refresh_token: refresh_token)
  end

  @doc """
  Garante um access token válido para a conexão, renovando (e persistindo)
  quando necessário — único ponto que checa expiração; todo client de
  `GoogleCalendar` chama isto antes de falar com a API do Google.
  """
  def get_valid_access_token(connection) do
    if expiring_soon?(connection.access_token_expires_at) do
      with {:ok, token_data} <- refresh_access_token(connection.refresh_token),
           {:ok, updated} <-
             QuizProject.Accounts.update_google_calendar_tokens(connection, %{
               access_token: token_data.access_token,
               refresh_token: token_data.refresh_token,
               access_token_expires_at: token_data.expires_at
             }) do
        {:ok, updated.access_token}
      end
    else
      {:ok, connection.access_token}
    end
  end

  @doc "Revoga um token no Google (chamador trata como melhor esforço)."
  def revoke(token) do
    request =
      Req.new(
        [url: @revoke_url, form: [token: token], receive_timeout: 10_000] ++
          Application.get_env(:quiz_project, :google_req_options, [])
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_token(form) do
    request =
      Req.new(
        [
          url: @token_url,
          form: form ++ [client_id: client_id(), client_secret: client_secret()],
          receive_timeout: 10_000
        ] ++ Application.get_env(:quiz_project, :google_req_options, [])
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, token_data(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[GoogleCalendar.OAuth] Erro HTTP #{status} do Google: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("[GoogleCalendar.OAuth] Erro de conexão com o Google: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp token_data(body) do
    %{
      access_token: Map.fetch!(body, "access_token"),
      refresh_token: Map.get(body, "refresh_token"),
      expires_at: DateTime.add(DateTime.utc_now(), Map.fetch!(body, "expires_in"), :second)
    }
  end

  # Margem de 60s pra nunca usar um token que expira no meio de uma chamada.
  defp expiring_soon?(expires_at) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second) <= 60
  end

  defp client_id, do: Application.fetch_env!(:quiz_project, :google_client_id)
  defp client_secret, do: Application.fetch_env!(:quiz_project, :google_client_secret)
  defp redirect_uri, do: Application.fetch_env!(:quiz_project, :google_oauth_redirect_uri)
end
