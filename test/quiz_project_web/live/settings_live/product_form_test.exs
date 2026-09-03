defmodule QuizProjectWeb.SettingsLive.ProductFormTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Store

  setup :register_and_log_in_user

  describe "novo produto" do
    test "cadastra sem imagem e volta para a lista de produtos", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings/products/new")

      {:ok, _view, html} =
        view
        |> form("#product-form",
          product: %{name: "Vale-café", description: "Um café por conta da casa.", price: "350"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/settings?tab=store&store_tab=products")

      assert html =~ "cadastrado."
      assert html =~ "Vale-café"
      assert [product] = Store.list_products(user)
      assert product.price == 350
    end

    test "cadastra com imagem, que vira a capa", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings/products/new")

      entrada =
        file_input(view, "#product-form", :images, [
          %{name: "capa.png", content: png_bytes(), type: "image/png"}
        ])

      render_upload(entrada, "capa.png")

      view
      |> form("#product-form",
        product: %{name: "Com foto", description: "Descrição.", price: "10"}
      )
      |> render_submit()

      assert [product] = Store.list_products(user)
      assert {:ok, %{images: [image]}} = Store.get_product(product.id, user)
      assert image.position == 0
    end

    test "recusa preço inválido com flash de erro", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/products/new")

      html =
        view
        |> form("#product-form", product: %{name: "X", description: "Y", price: "0"})
        |> render_submit()

      assert html =~ "Não foi possível salvar"
    end

    test "pré-visualização acompanha o que é digitado", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/products/new")

      html =
        view
        |> form("#product-form", product: %{name: "Nome ao vivo", description: "", price: ""})
        |> render_change()

      assert html =~ "Nome ao vivo"
    end

    test "cancelar volta para a lista de produtos sem criar nada", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings/products/new")

      assert has_element?(view, ~s(a[href="/settings?tab=store&store_tab=products"]), "Cancelar")
      assert Store.list_products(user) == []
    end
  end

  describe "editar produto" do
    test "vem pré-preenchido e salva as mudanças", %{conn: conn, user: user} do
      {:ok, product} =
        Store.create_product(user, %{name: "Vale-café", description: "Um café.", price: 100})

      {:ok, view, html} = live(conn, ~p"/settings/products/#{product.id}/edit")

      assert html =~ "Editar produto"
      assert has_element?(view, "input[name='product[name]'][value='Vale-café']")

      {:ok, _view, html} =
        view
        |> form("#product-form",
          product: %{name: "Vale-café duplo", description: "Dois cafés.", price: "180"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/settings?tab=store&store_tab=products")

      assert html =~ "atualizado."
      assert html =~ "Vale-café duplo"

      assert {:ok, updated} = Store.get_product(product.id, user)
      assert updated.name == "Vale-café duplo"
      assert updated.price == 180
    end

    test "mostra e permite remover imagens existentes", %{conn: conn, user: user} do
      {:ok, product} =
        Store.create_product(user, %{name: "Vale-café", description: "Um café.", price: 100})

      {:ok, image} = Store.add_product_image(product, user, "#{product.id}/capa.png")

      {:ok, view, _html} = live(conn, ~p"/settings/products/#{product.id}/edit")

      assert has_element?(view, "img")

      view |> element("button[phx-value-id='#{image.id}']") |> render_click()

      assert {:ok, %{images: []}} = Store.get_product(product.id, user)
    end

    test "produto de outro usuário redireciona com flash", %{conn: conn} do
      {:ok, other} =
        QuizProject.Accounts.register_user(%{email: "outro@teste.com", password: "senha12345"},
          authorize?: false
        )

      {:ok, product} =
        Store.create_product(other, %{name: "Alheio", description: "Não é seu.", price: 100})

      {:ok, _view, html} =
        conn
        |> live(~p"/settings/products/#{product.id}/edit")
        |> follow_redirect(conn, ~p"/settings?tab=store&store_tab=products")

      assert html =~ "Produto não encontrado."
    end
  end

  # PNG 1x1 mínimo válido, só para exercitar o upload de ponta a ponta.
  defp png_bytes do
    <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6,
      0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
      13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  end
end
