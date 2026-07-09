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

  # Notificações fixas das execuções em background: carrega as não lidas do
  # usuário, assina o tópico PubSub e mantém o assign `:notifications` que o
  # layout renderiza como pilha fixa em todas as páginas autenticadas. Elas
  # sobrevivem a navegação e recarga — só somem quando o usuário dispensa ou
  # abre o link. Os eventos de dispensar/abrir são tratados aqui (`:halt`);
  # a mensagem PubSub segue com `:cont` para cada LiveView também reagir
  # (ex.: o painel recarrega a lista ao vivo).
  def on_mount(:notify_attempts, _params, _session, socket) do
    socket =
      if socket.assigns[:current_user] do
        user_id = socket.assigns.current_user.id

        if Phoenix.LiveView.connected?(socket) do
          QuizProject.Attempts.Notifier.subscribe_user(user_id)
        end

        socket
        |> Phoenix.Component.assign(
          :notifications,
          QuizProject.Notifications.list_unread(user_id)
        )
        |> Phoenix.LiveView.attach_hook(
          :attempt_notifications,
          :handle_info,
          &handle_attempt_notification/2
        )
        |> Phoenix.LiveView.attach_hook(
          :notification_events,
          :handle_event,
          &handle_notification_event/3
        )
      else
        Phoenix.Component.assign(socket, :notifications, [])
      end

    {:cont, socket}
  end

  defp handle_attempt_notification({:attempt_finished, _info}, socket) do
    {:cont, reload_notifications(socket)}
  end

  defp handle_attempt_notification(_message, socket), do: {:cont, socket}

  defp handle_notification_event("dismiss_notification", %{"id" => id}, socket) do
    QuizProject.Notifications.mark_read(id, socket.assigns.current_user.id)
    {:halt, reload_notifications(socket)}
  end

  # navega para o `path` guardado na notificação (nunca o do cliente) e a
  # marca como lida
  defp handle_notification_event("open_notification", %{"id" => id}, socket) do
    case QuizProject.Notifications.mark_read(id, socket.assigns.current_user.id) do
      {:ok, notification} ->
        {:halt, Phoenix.LiveView.push_navigate(socket, to: notification.path)}

      _ ->
        {:halt, reload_notifications(socket)}
    end
  end

  defp handle_notification_event(_event, _params, socket), do: {:cont, socket}

  defp reload_notifications(socket) do
    Phoenix.Component.assign(
      socket,
      :notifications,
      QuizProject.Notifications.list_unread(socket.assigns.current_user.id)
    )
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
