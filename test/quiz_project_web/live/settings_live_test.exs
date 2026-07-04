defmodule QuizProjectWeb.SettingsLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Accounts
  alias QuizProject.Accounts.User

  setup :register_and_log_in_user

  test "exige login" do
    assert {:error, {:redirect, %{to: "/entrar"}}} = live(build_conn(), ~p"/configuracoes")
  end

  test "exibe as áreas principais", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/configuracoes")

    assert html =~ "Conta e API"
    assert has_element?(view, "#settings-page")
    assert has_element?(view, "#settings-tab-profile")
    assert has_element?(view, "#settings-tab-security")
    assert has_element?(view, "#settings-tab-tokens")
    assert has_element?(view, "#profile-form")
    assert has_element?(view, "span#desktop-nav-account[aria-current=page]")
    assert has_element?(view, "a#desktop-nav-quizzes")
    assert has_element?(view, "#appearance-control")
  end

  test "atualiza o perfil", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

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
    {:ok, view, _html} = live(conn, ~p"/configuracoes")
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
    {:ok, view, _html} = live(conn, ~p"/configuracoes")
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
    {:ok, view, _html} = live(conn, ~p"/configuracoes?tab=tokens")

    assert has_element?(view, "#token-settings")
    assert has_element?(view, "#token-form")
  end
end
