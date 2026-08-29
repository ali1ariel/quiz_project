defmodule QuizProjectWeb.SettingsLiveTest do
  # `async: false`: o teste de desconexão do Google Agenda manipula
  # `google_req_options`, configuração global do app (mesmo motivo de
  # `QuizProject.GoogleCalendar.OAuthTest` ser `async: false`).
  use QuizProjectWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias QuizProject.Accounts
  alias QuizProject.Accounts.User

  setup :register_and_log_in_user

  test "exige login" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/settings")
  end

  test "exibe as áreas principais", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "Conta e API"
    assert has_element?(view, "#settings-page")
    assert has_element?(view, "#settings-tab-profile")
    assert has_element?(view, "#settings-tab-security")
    assert has_element?(view, "#settings-tab-tokens")
    assert has_element?(view, "#profile-form")
    assert has_element?(view, ~s(a#desktop-nav-account[aria-current=page][href="/settings"]))
    assert has_element?(view, "a#desktop-nav-quizzes")
    assert has_element?(view, "#appearance-control")
  end

  test "atualiza o perfil", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#profile-form", %{
      "profile" => %{"name" => "Pessoa Atualizada", "email" => "atualizada@teste.com"}
    })
    |> render_submit()

    assert {:ok, updated} = Accounts.get_user_by_id(user.id, authorize?: false)
    assert updated.name == "Pessoa Atualizada"
    assert to_string(updated.email) == "atualizada@teste.com"
  end

  test "troca a senha", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    view |> element("#settings-tab-security") |> render_click()

    assert has_element?(view, "#password-form")

    view
    |> form("#password-form", %{
      "password" => %{
        "current_password" => "senha12345",
        "password" => "senha-nova-123",
        "password_confirmation" => "senha-nova-123"
      }
    })
    |> render_submit()

    assert :error = User.authenticate(to_string(user.email), "senha12345")
    assert {:ok, _authenticated} = User.authenticate(to_string(user.email), "senha-nova-123")
  end

  test "cria, mostra uma vez e revoga token", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    view |> element("#settings-tab-tokens") |> render_click()

    assert has_element?(view, "#token-form")
    assert has_element?(view, "#tokens-empty")
    assert has_element?(view, "#token-api-docs-link[href='/api/docs']")

    view
    |> form("#token-form", %{"token" => %{"name" => "Agente local"}})
    |> render_submit()

    assert has_element?(view, "#new-token-panel")
    assert has_element?(view, "#new-token-value")

    assert [token] = Accounts.list_api_tokens(user)
    assert has_element?(view, "#api-token-#{token.id}")
    assert has_element?(view, "#revoke-token-#{token.id}")

    view |> element("#close-new-token") |> render_click()
    refute has_element?(view, "#new-token-panel")

    view |> element("#revoke-token-#{token.id}") |> render_click()
    refute has_element?(view, "#api-token-#{token.id}")
    assert Accounts.list_api_tokens(user) == []
  end

  test "abre diretamente a aba de tokens pela URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?tab=tokens")

    assert has_element?(view, "#token-settings")
    assert has_element?(view, "#token-form")
  end

  describe "aba do Google Agenda" do
    test "sem conexão, mostra o link pra conectar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?tab=calendar")

      assert has_element?(view, "#calendar-settings")
      assert has_element?(view, ~s(a#connect-google-calendar[href="/settings/google/connect"]))
      refute has_element?(view, "#disconnect-google-calendar")
    end

    test "com o ambiente sem GOOGLE_CLIENT_ID, mostra aviso de não configurado", %{conn: conn} do
      original = Application.get_env(:quiz_project, :google_client_id)
      Application.delete_env(:quiz_project, :google_client_id)
      on_exit(fn -> Application.put_env(:quiz_project, :google_client_id, original) end)

      {:ok, view, _html} = live(conn, ~p"/settings?tab=calendar")

      assert render(view) =~ "ainda não configurada neste ambiente"
      refute has_element?(view, "#connect-google-calendar")
    end

    test "com conexão salva, mostra o e-mail conectado e permite desconectar", %{
      conn: conn,
      user: user
    } do
      Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
      on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

      {:ok, _connection} =
        Accounts.upsert_google_calendar_connection(user, %{
          google_account_email: "dono@gmail.com",
          access_token: "access-1",
          refresh_token: "refresh-1",
          access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          calendar_id: "calendar-abc"
        })

      {:ok, view, _html} = live(conn, ~p"/settings?tab=calendar")

      assert render(view) =~ "dono@gmail.com"
      assert has_element?(view, "#disconnect-google-calendar")
      refute has_element?(view, "#connect-google-calendar")

      view |> element("#disconnect-google-calendar") |> render_click()

      refute has_element?(view, "#disconnect-google-calendar")
      assert has_element?(view, "#connect-google-calendar")
      assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
    end
  end
end
