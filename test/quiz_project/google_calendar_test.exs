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

  defp stub_happy_path do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{
            "access_token" => "access-1",
            "refresh_token" => "refresh-1",
            "expires_in" => 3600
          })

        "/oauth2/v2/userinfo" ->
          Req.Test.json(conn, %{"email" => "dono@gmail.com"})

        "/calendar/v3/calendars" ->
          Req.Test.json(conn, %{"id" => "calendar-abc"})
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
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{
            "access_token" => "access-2",
            "refresh_token" => "refresh-2",
            "expires_in" => 3600
          })

        "/oauth2/v2/userinfo" ->
          Req.Test.json(conn, %{"email" => "outra-conta@gmail.com"})

        "/calendar/v3/calendars" ->
          Req.Test.json(conn, %{"id" => "calendar-novo"})
      end
    end)

    {:ok, second} = GoogleCalendar.connect(user, "auth-code-456")

    assert second.id != first.id
    assert second.google_account_email == "outra-conta@gmail.com"
    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == second.id
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
end
