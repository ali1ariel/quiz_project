defmodule QuizProjectWeb.GoogleAuthController do
  use QuizProjectWeb, :controller

  alias QuizProject.GoogleCalendar

  require Logger

  @doc "Inicia o fluxo OAuth: guarda um `state` anti-CSRF na sessão e redireciona pro Google."
  def connect(conn, _params) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

    conn
    |> put_session(:google_oauth_state, state)
    |> redirect(external: GoogleCalendar.authorize_url(state))
  end

  def callback(conn, %{"error" => error}) do
    Logger.warning("[GoogleAuthController] Consentimento negado pelo usuário: #{error}")

    conn
    |> put_flash(:error, "Conexão com o Google Agenda cancelada.")
    |> redirect(to: ~p"/settings?tab=calendar")
  end

  def callback(conn, %{"state" => state, "code" => code}) do
    expected_state = get_session(conn, :google_oauth_state)
    conn = delete_session(conn, :google_oauth_state)

    if valid_state?(state, expected_state) do
      case GoogleCalendar.connect(conn.assigns.current_user, code) do
        {:ok, _connection} ->
          conn
          |> put_flash(:info, "Google Agenda conectado com sucesso.")
          |> redirect(to: ~p"/settings?tab=calendar")

        {:error, error} ->
          Logger.error(
            "[GoogleAuthController] Falha ao conectar Google Agenda: #{inspect(error)}"
          )

          conn
          |> put_flash(:error, humanize_error(error))
          |> redirect(to: ~p"/settings?tab=calendar")
      end
    else
      conn
      |> put_flash(:error, "Não foi possível confirmar a conexão com o Google. Tente de novo.")
      |> redirect(to: ~p"/settings?tab=calendar")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Resposta inesperada do Google.")
    |> redirect(to: ~p"/settings?tab=calendar")
  end

  defp valid_state?(state, expected_state) do
    is_binary(state) and is_binary(expected_state) and
      Plug.Crypto.secure_compare(state, expected_state)
  end

  defp humanize_error({:http_error, _status, _body}),
    do: "O Google recusou a solicitação. Tente conectar de novo."

  defp humanize_error(%Ash.Error.Invalid{}),
    do: "Não foi possível salvar a conexão. Tente conectar de novo."

  defp humanize_error(_error), do: "Não foi possível conectar ao Google Agenda agora."
end
