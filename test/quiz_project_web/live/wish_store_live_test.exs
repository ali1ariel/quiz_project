defmodule QuizProjectWeb.WishStoreLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Priorities

  setup :register_and_log_in_user

  describe "Wallet" do
    test "vazia mostra saldo zero e nenhum lançamento", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/wish-store")

      assert html =~ "Nenhum lançamento ainda."
      assert html =~ "0"
    end

    test "mostra saldo e extrato após concluir uma atividade com pontos", %{
      conn: conn,
      user: user
    } do
      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ler capítulo 1", store_points: 10})

      {:ok, _} = Priorities.complete_activity(activity, user)

      {:ok, view, html} = live(conn, ~p"/wish-store")

      assert html =~ "+10"
      assert has_element?(view, "li", "Atividade concluída: \"Ler capítulo 1\"")
    end

    test "sub-navegação marca Carteira como aba ativa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wish-store")

      assert has_element?(view, "a.bg-primary", "Carteira")
    end
  end
end
