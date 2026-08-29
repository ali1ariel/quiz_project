defmodule QuizProject.GoogleCalendar.OAuthTest do
  # `google_req_options` é configuração global do app — não pode rodar em
  # paralelo com outro teste que também a manipule (mesmo padrão de
  # `AIProvidersTest`, que usa `:ai_req_options` da mesma forma).
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar.OAuth

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
        access_token: "access-atual",
        refresh_token: "refresh-atual",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        calendar_id: "calendar-1"
      })

    %{user: user, connection: connection}
  end

  test "authorize_url inclui client_id, redirect_uri, escopo e o state" do
    url = OAuth.authorize_url("state-xyz")

    assert url =~ "https://accounts.google.com/o/oauth2/v2/auth?"
    assert url =~ "client_id=test-client-id"
    assert url =~ "state=state-xyz"
    assert url =~ URI.encode_www_form("https://www.googleapis.com/auth/calendar")
    assert url =~ "access_type=offline"
    assert url =~ "prompt=consent"
  end

  test "get_valid_access_token reaproveita o token quando ele ainda não está perto de expirar",
       %{connection: connection} do
    Req.Test.stub(__MODULE__, fn _conn -> flunk("não deveria chamar o Google") end)

    assert {:ok, "access-atual"} = OAuth.get_valid_access_token(connection)
  end

  test "get_valid_access_token renova e persiste quando o token está perto de expirar", %{
    connection: connection
  } do
    {:ok, connection} =
      Accounts.update_google_calendar_tokens(connection, %{
        access_token: connection.access_token,
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 30, :second)
      })

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"access_token" => "access-novo", "expires_in" => 3600})
    end)

    assert {:ok, "access-novo"} = OAuth.get_valid_access_token(connection)

    assert {:ok, updated} = Accounts.get_google_calendar_connection(%{id: connection.user_id})
    assert updated.access_token == "access-novo"
    # refresh_token não veio na resposta do refresh — mantém o anterior.
    assert updated.refresh_token == "refresh-atual"
  end

  test "get_valid_access_token propaga erro HTTP do Google sem persistir nada", %{
    connection: connection
  } do
    {:ok, connection} =
      Accounts.update_google_calendar_tokens(connection, %{
        access_token: connection.access_token,
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 30, :second)
      })

    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
    end)

    assert {:error, {:http_error, 400, _body}} = OAuth.get_valid_access_token(connection)
  end

  test "revoke devolve :ok quando o Google confirma a revogação", %{connection: connection} do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

    assert :ok = OAuth.revoke(connection.refresh_token)
  end
end
