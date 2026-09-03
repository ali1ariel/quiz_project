defmodule QuizProjectWeb.WishStoreLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Priorities
  alias QuizProject.Store

  setup :register_and_log_in_user

  describe "Wallet" do
    test "vazia mostra saldo zero e nenhum lançamento", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/wish-store/wallet")

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

      {:ok, view, html} = live(conn, ~p"/wish-store/wallet")

      assert html =~ "+10"
      assert has_element?(view, "li", "Atividade concluída: \"Ler capítulo 1\"")
    end

    test "sub-navegação marca Carteira como aba ativa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wish-store/wallet")

      assert has_element?(view, "a.bg-primary", "Carteira")
    end
  end

  describe "Store (listagem)" do
    test "é a tela padrão da Wish Store", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/wish-store")

      assert html =~ "Nenhum produto cadastrado ainda."
      assert has_element?(view, "a.bg-primary", "Loja")
    end

    test "lista produtos do usuário com preço e saldo", %{conn: conn, user: user} do
      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ganhar pontos", store_points: 100})

      {:ok, _} = Priorities.complete_activity(activity, user)

      {:ok, _product} =
        Store.create_product(user, %{name: "Vale-café", description: "Um café.", price: 100})

      {:ok, _view, html} = live(conn, ~p"/wish-store")

      assert html =~ "Vale-café"
      assert html =~ "Ver detalhes"
    end

    test "marca produto acima do saldo como indisponível", %{conn: conn, user: user} do
      {:ok, _product} =
        Store.create_product(user, %{name: "Caro", description: "Muito.", price: 999})

      {:ok, view, _html} = live(conn, ~p"/wish-store")

      assert has_element?(view, "span", "Faltam 999 pts")
    end
  end

  describe "Show (detalhe do produto)" do
    test "redireciona com flash quando o produto não existe", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> live(~p"/wish-store/#{Ecto.UUID.generate()}")
        |> follow_redirect(conn, ~p"/wish-store")

      assert html =~ "Produto não encontrado."
    end

    test "mostra nome, descrição e preço", %{conn: conn, user: user} do
      {:ok, product} =
        Store.create_product(user, %{name: "Vale-café", description: "Um café.", price: 100})

      {:ok, _view, html} = live(conn, ~p"/wish-store/#{product.id}")

      assert html =~ "Vale-café"
      assert html =~ "Um café."
    end

    test "resgatar debita a carteira e atualiza o saldo na tela", %{conn: conn, user: user} do
      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ganhar pontos", store_points: 100})

      {:ok, _} = Priorities.complete_activity(activity, user)

      {:ok, product} =
        Store.create_product(user, %{name: "Vale-café", description: "Um café.", price: 40})

      {:ok, view, _html} = live(conn, ~p"/wish-store/#{product.id}")

      html = view |> element("button", "Resgatar por 40 pontos") |> render_click()

      assert html =~ "resgatado!"
      assert html =~ "60"
      assert Priorities.wallet_balance(user) == 60
    end

    test "botão de resgate fica desabilitado sem saldo suficiente", %{conn: conn, user: user} do
      {:ok, product} =
        Store.create_product(user, %{name: "Caro", description: "Muito.", price: 999})

      {:ok, view, _html} = live(conn, ~p"/wish-store/#{product.id}")

      assert has_element?(view, "button[disabled]", "Resgatar por 999 pontos")
    end
  end
end
