defmodule QuizProjectWeb.Api.GoogleCalendarWebhookControllerTest do
  # Ver comentário em `QuizProject.GoogleCalendar.OAuthTest` sobre
  # `google_req_options` ser configuração global do app.
  use QuizProjectWeb.ConnCase, async: false

  alias QuizProject.Accounts

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)

    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, connection} =
      Accounts.upsert_google_calendar_connection(user, %{
        google_account_email: "dono@gmail.com",
        access_token: "access-1",
        refresh_token: "refresh-1",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        calendar_id: "calendar-1"
      })

    channel_token = "segredo-do-canal"

    {:ok, connection} =
      Accounts.update_google_calendar_watch_channel(connection, %{
        channel_id: "canal-1",
        channel_token_hash: :crypto.hash(:sha256, channel_token) |> Base.encode16(case: :lower),
        channel_resource_id: "recurso-1",
        channel_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    %{user: user, connection: connection, channel_token: channel_token}
  end

  test "notificação válida com resource-state exists dispara a reconciliação", %{
    conn: conn,
    channel_token: channel_token
  } do
    Req.Test.stub(__MODULE__, fn req_conn ->
      Req.Test.json(req_conn, %{"items" => [], "nextSyncToken" => "sync-token-1"})
    end)

    conn =
      conn
      |> Plug.Conn.put_req_header("x-goog-channel-id", "canal-1")
      |> Plug.Conn.put_req_header("x-goog-channel-token", channel_token)
      |> Plug.Conn.put_req_header("x-goog-resource-state", "exists")
      |> post(~p"/api/google/calendar/webhook")

    assert conn.status == 200

    assert {:ok, fetched} = Accounts.get_google_calendar_connection_by_channel_id("canal-1")
    assert fetched.sync_token == "sync-token-1"
  end

  test "resource-state sync (verificação inicial do Google) não dispara reconciliação", %{
    conn: conn,
    channel_token: channel_token
  } do
    Req.Test.stub(__MODULE__, fn _req_conn -> flunk("não deveria chamar o Google") end)

    conn =
      conn
      |> Plug.Conn.put_req_header("x-goog-channel-id", "canal-1")
      |> Plug.Conn.put_req_header("x-goog-channel-token", channel_token)
      |> Plug.Conn.put_req_header("x-goog-resource-state", "sync")
      |> post(~p"/api/google/calendar/webhook")

    assert conn.status == 200
  end

  test "token de canal inválido não dispara reconciliação, mas ainda responde 200", %{conn: conn} do
    Req.Test.stub(__MODULE__, fn _req_conn -> flunk("não deveria chamar o Google") end)

    conn =
      conn
      |> Plug.Conn.put_req_header("x-goog-channel-id", "canal-1")
      |> Plug.Conn.put_req_header("x-goog-channel-token", "token-errado")
      |> Plug.Conn.put_req_header("x-goog-resource-state", "exists")
      |> post(~p"/api/google/calendar/webhook")

    assert conn.status == 200
  end

  test "channel_id desconhecido não quebra e ainda responde 200", %{conn: conn} do
    Req.Test.stub(__MODULE__, fn _req_conn -> flunk("não deveria chamar o Google") end)

    conn =
      conn
      |> Plug.Conn.put_req_header("x-goog-channel-id", "canal-inexistente")
      |> Plug.Conn.put_req_header("x-goog-channel-token", "qualquer")
      |> Plug.Conn.put_req_header("x-goog-resource-state", "exists")
      |> post(~p"/api/google/calendar/webhook")

    assert conn.status == 200
  end

  test "headers ausentes não quebram e ainda respondem 200", %{conn: conn} do
    conn = post(conn, ~p"/api/google/calendar/webhook")
    assert conn.status == 200
  end
end
