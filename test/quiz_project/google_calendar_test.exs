defmodule QuizProject.GoogleCalendarTest do
  # Ver comentário em `OAuthTest` sobre `google_req_options` ser global.
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)

    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user}
  end

  defp stub_happy_path(calendar_id \\ "calendar-abc") do
    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        conn.request_path == "/token" ->
          Req.Test.json(conn, %{
            "access_token" => "access-1",
            "refresh_token" => "refresh-1",
            "expires_in" => 3600
          })

        conn.request_path == "/oauth2/v2/userinfo" ->
          Req.Test.json(conn, %{"email" => "dono@gmail.com"})

        conn.request_path == "/calendar/v3/calendars" ->
          Req.Test.json(conn, %{"id" => calendar_id})

        String.ends_with?(conn.request_path, "/events/watch") ->
          Req.Test.json(conn, %{"resourceId" => "resource-1", "expiration" => "9999999999999"})

        conn.method == "GET" and String.ends_with?(conn.request_path, "/events") ->
          Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-inicial"})
      end
    end)
  end

  test "connect troca o código, cria o calendário dedicado e salva a conexão", %{user: user} do
    stub_happy_path()

    assert {:ok, connection} = GoogleCalendar.connect(user, "auth-code-123")

    assert connection.google_account_email == "dono@gmail.com"
    assert connection.calendar_id == "calendar-abc"
    assert connection.access_token == "access-1"
    assert connection.refresh_token == "refresh-1"

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == connection.id
  end

  test "connect reconectando substitui a conexão anterior", %{user: user} do
    stub_happy_path()
    {:ok, first} = GoogleCalendar.connect(user, "auth-code-123")

    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        conn.request_path == "/token" ->
          Req.Test.json(conn, %{
            "access_token" => "access-2",
            "refresh_token" => "refresh-2",
            "expires_in" => 3600
          })

        conn.request_path == "/oauth2/v2/userinfo" ->
          Req.Test.json(conn, %{"email" => "outra-conta@gmail.com"})

        conn.request_path == "/calendar/v3/calendars" ->
          Req.Test.json(conn, %{"id" => "calendar-novo"})

        String.ends_with?(conn.request_path, "/events/watch") ->
          Req.Test.json(conn, %{"resourceId" => "resource-2", "expiration" => "9999999999999"})

        conn.method == "GET" and String.ends_with?(conn.request_path, "/events") ->
          Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-novo"})
      end
    end)

    {:ok, second} = GoogleCalendar.connect(user, "auth-code-456")

    assert second.id != first.id
    assert second.google_account_email == "outra-conta@gmail.com"
    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == second.id
  end

  test "connect registra o watch channel e captura o sync_token inicial", %{user: user} do
    stub_happy_path()

    assert {:ok, connection} = GoogleCalendar.connect(user, "auth-code-123")

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == connection.id
    assert fetched.channel_id != nil
    assert fetched.channel_resource_id == "resource-1"
    assert fetched.channel_token_hash != nil
    assert fetched.channel_expires_at != nil
    assert fetched.sync_token == "sync-token-inicial"

    assert {:ok, by_channel} =
             Accounts.get_google_calendar_connection_by_channel_id(fetched.channel_id)

    assert by_channel.id == connection.id
  end

  test "falha ao registrar o watch não impede a conexão (só fica sem sync de entrada por ora)",
       %{user: user} do
    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        conn.request_path == "/token" ->
          Req.Test.json(conn, %{
            "access_token" => "access-1",
            "refresh_token" => "refresh-1",
            "expires_in" => 3600
          })

        conn.request_path == "/oauth2/v2/userinfo" ->
          Req.Test.json(conn, %{"email" => "dono@gmail.com"})

        conn.request_path == "/calendar/v3/calendars" ->
          Req.Test.json(conn, %{"id" => "calendar-abc"})

        String.ends_with?(conn.request_path, "/events/watch") ->
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{"error" => "webhook não alcançável"})
      end
    end)

    assert {:ok, connection} = GoogleCalendar.connect(user, "auth-code-123")

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == connection.id
    assert is_nil(fetched.channel_id)
    assert fetched.last_sync_error != nil
  end

  test "connect propaga falha na troca do código sem criar conexão", %{user: user} do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
    end)

    assert {:error, {:http_error, 400, _body}} = GoogleCalendar.connect(user, "codigo-invalido")
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end

  test "disconnect revoga o token e apaga a conexão salva", %{user: user} do
    stub_happy_path()
    {:ok, _connection} = GoogleCalendar.connect(user, "auth-code-123")

    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

    assert {:ok, _} = GoogleCalendar.disconnect(user)
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end

  test "disconnect sem conexão existente não quebra", %{user: user} do
    assert {:error, :not_found} = GoogleCalendar.disconnect(user)
  end

  test "disconnect encerra o canal de push notifications registrado", %{user: user} do
    stub_happy_path()
    {:ok, _connection} = GoogleCalendar.connect(user, "auth-code-123")
    assert {:ok, %{channel_id: channel_id}} = Accounts.get_google_calendar_connection(user)

    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      if String.ends_with?(conn.request_path, "/channels/stop") do
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:stop_body, Jason.decode!(body)})
      end

      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert {:ok, _} = GoogleCalendar.disconnect(user)

    assert_received {:stop_body, %{"id" => ^channel_id, "resourceId" => "resource-1"}}
  end
end
