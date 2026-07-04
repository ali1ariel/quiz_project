defmodule QuizProjectWeb.UserAuth do
  @moduledoc """
  Plugs e hooks de autenticação.

  Dois conceitos convivem aqui:

    * `current_user` — usuário logado (obrigatório para criar quizzes).
    * `participant_token` — token de sessão sempre presente, usado para
      vincular tentativas de participantes anônimos. Quando o usuário loga
      no meio de uma tentativa, o token permite associar as tentativas
      anônimas à conta.
  """

  use QuizProjectWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias QuizProject.Accounts

  ## Plugs

  def fetch_current_user(conn, _opts) do
    user =
      with user_id when is_binary(user_id) <- get_session(conn, :user_id),
           {:ok, user} <- Accounts.get_user_by_id(user_id, authorize?: false) do
        user
      else
        _ -> nil
      end

    assign(conn, :current_user, user)
  end

  def ensure_participant_token(conn, _opts) do
    case get_session(conn, :participant_token) do
      token when is_binary(token) ->
        assign(conn, :participant_token, token)

      _ ->
        token = generate_participant_token()

        conn
        |> put_session(:participant_token, token)
        |> assign(:participant_token, token)
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Você precisa entrar para acessar essa página.")
      |> put_session(:user_return_to, current_path(conn))
      |> redirect(to: ~p"/entrar")
      |> halt()
    end
  end

  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn |> redirect(to: ~p"/painel") |> halt()
    else
      conn
    end
  end

  ## Sessão

  def log_in_user(conn, user) do
    return_to = get_session(conn, :user_return_to)
    participant_token = get_session(conn, :participant_token)

    QuizProject.Attempts.adopt_anonymous_attempts(user, participant_token)

    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> put_session(:participant_token, participant_token || generate_participant_token())
    |> delete_session(:user_return_to)
    |> redirect(to: return_to || ~p"/painel")
  end

  def log_out_user(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  ## LiveView on_mount hooks

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Você precisa entrar para acessar essa página.")
       |> Phoenix.LiveView.redirect(to: ~p"/entrar")}
    end
  end

  defp mount_current_user(socket, session) do
    socket
    |> Phoenix.Component.assign_new(:current_user, fn ->
      with user_id when is_binary(user_id) <- session["user_id"],
           {:ok, user} <- Accounts.get_user_by_id(user_id, authorize?: false) do
        user
      else
        _ -> nil
      end
    end)
    |> Phoenix.Component.assign_new(:participant_token, fn ->
      session["participant_token"]
    end)
  end

  defp generate_participant_token do
    Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  end
end
