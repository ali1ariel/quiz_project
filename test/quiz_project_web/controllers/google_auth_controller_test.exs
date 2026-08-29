defmodule QuizProjectWeb.GoogleAuthControllerTest do
  # Ver comentário em `QuizProject.GoogleCalendar.OAuthTest` sobre
  # `google_req_options` ser configuração global do app.
  use QuizProjectWeb.ConnCase, async: false

  alias QuizProject.Accounts

  setup :register_and_log_in_user

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)
    :ok
  end

  test "connect guarda o state na sessão e redireciona pro Google", %{conn: conn} do
    conn = get(conn, ~p"/settings/google/connect")

    location = redirected_to(conn, 302)
    assert location =~ "https://accounts.google.com/o/oauth2/v2/auth?"
    assert location =~ "client_id=test-client-id"
    assert location =~ "prompt=consent"

    state = get_session(conn, :google_oauth_state)
    assert is_binary(state)
    assert URI.decode_query(URI.parse(location).query)["state"] == state
  end

  test "callback com consentimento negado mostra erro e não conecta", %{conn: conn, user: user} do
    conn = get(conn, ~p"/settings/google/callback", %{"error" => "access_denied"})

    assert redirected_to(conn) == ~p"/settings?tab=calendar"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelada"
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end

  test "callback com state divergente não conecta", %{conn: conn, user: user} do
    conn = get(conn, ~p"/settings/google/connect")
    conn = recycle(conn)

    conn = get(conn, ~p"/settings/google/callback", %{"state" => "state-forjado", "code" => "x"})

    assert redirected_to(conn) == ~p"/settings?tab=calendar"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Não foi possível confirmar"
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end

  test "callback com state válido conecta o usuário ao Google Agenda", %{conn: conn, user: user} do
    conn = get(conn, ~p"/settings/google/connect")
    state = get_session(conn, :google_oauth_state)
    conn = recycle(conn)

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
          Req.Test.json(conn, %{"resourceId" => "resource-1", "expiration" => "9999999999999"})

        conn.method == "GET" and String.ends_with?(conn.request_path, "/events") ->
          Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-inicial"})
      end
    end)

    conn = get(conn, ~p"/settings/google/callback", %{"state" => state, "code" => "codigo-ok"})

    assert redirected_to(conn) == ~p"/settings?tab=calendar"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "conectado"

    assert {:ok, connection} = Accounts.get_google_calendar_connection(user)
    assert connection.google_account_email == "dono@gmail.com"
    assert connection.calendar_id == "calendar-abc"

    # O state é de uso único — não pode ser reaproveitado numa nova chamada.
    refute get_session(conn, :google_oauth_state)
  end

  test "callback com falha na troca do código mostra erro e não conecta", %{
    conn: conn,
    user: user
  } do
    conn = get(conn, ~p"/settings/google/connect")
    state = get_session(conn, :google_oauth_state)
    conn = recycle(conn)

    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
    end)

    conn = get(conn, ~p"/settings/google/callback", %{"state" => state, "code" => "codigo-ruim"})

    assert redirected_to(conn) == ~p"/settings?tab=calendar"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end
end
