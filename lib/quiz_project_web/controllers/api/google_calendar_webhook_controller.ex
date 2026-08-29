defmodule QuizProjectWeb.Api.GoogleCalendarWebhookController do
  @moduledoc """
  Recebe as notificações de push do canal `events.watch` registrado em
  `QuizProject.GoogleCalendar.connect/2` — o Google não manda o que mudou,
  só avisa que algo mudou (tudo em headers, corpo vazio); a reconciliação
  de verdade (`GoogleCalendar.reconcile/1`) busca os deltas depois.
  """
  use QuizProjectWeb, :controller

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar

  require Logger

  def notify(conn, _params) do
    with [channel_id] <- get_req_header(conn, "x-goog-channel-id"),
         [channel_token] <- get_req_header(conn, "x-goog-channel-token"),
         {:ok, connection} <- Accounts.get_google_calendar_connection_by_channel_id(channel_id),
         true <- GoogleCalendar.verify_channel_token?(connection, channel_token) do
      if resource_state(conn) == "exists" do
        QuizProject.Jobs.run(fn -> GoogleCalendar.reconcile(connection) end)
      end
    else
      _ ->
        Logger.warning(
          "[GoogleCalendarWebhookController] Notificação ignorada (canal/token ausente ou inválido)"
        )
    end

    # Sempre 200, mesmo quando ignorada: é o que o protocolo do Google
    # espera, e não vaza pra fora se um channel_id é válido ou não.
    send_resp(conn, 200, "")
  end

  defp resource_state(conn) do
    case get_req_header(conn, "x-goog-resource-state") do
      [state] -> state
      _ -> nil
    end
  end
end
