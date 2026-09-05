defmodule QuizProject.StoreTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Priorities
  alias QuizProject.Store

  setup do
    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "outro@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user, other: other}
  end

  defp product(user, attrs \\ %{}) do
    {:ok, product} =
      Store.create_product(
        user,
        Map.merge(
          %{name: "Vale-café", description: "Um café por conta da casa.", price: 100},
          attrs
        )
      )

    product
  end

  describe "create_product/2" do
    test "recusa preço zero ou negativo", %{user: user} do
      assert {:error, _} = Store.create_product(user, %{name: "X", description: "Y", price: 0})
      assert {:error, _} = Store.create_product(user, %{name: "X", description: "Y", price: -5})
    end

    test "aceita link_url e link_text juntos", %{user: user} do
      produto = product(user, %{link_url: "https://loja.com/item", link_text: "Ver na loja"})

      assert produto.link_url == "https://loja.com/item"
      assert produto.link_text == "Ver na loja"
    end

    test "recusa link_url sem link_text e vice-versa", %{user: user} do
      assert {:error, _} =
               Store.create_product(user, %{
                 name: "X",
                 description: "Y",
                 price: 10,
                 link_url: "https://loja.com/item"
               })

      assert {:error, _} =
               Store.create_product(user, %{
                 name: "X",
                 description: "Y",
                 price: 10,
                 link_text: "Ver na loja"
               })
    end
  end

  describe "list_products/1" do
    test "só lista produtos do próprio usuário, mais recentes primeiro", %{
      user: user,
      other: other
    } do
      _alheio = product(other)
      primeiro = product(user, %{name: "Primeiro"})
      segundo = product(user, %{name: "Segundo"})

      assert [listado_segundo, listado_primeiro] = Store.list_products(user)
      assert listado_segundo.id == segundo.id
      assert listado_primeiro.id == primeiro.id
    end
  end

  describe "get_product/2" do
    test "recusa produto de outro usuário", %{user: user, other: other} do
      alheio = product(other)

      assert {:error, :unauthorized} = Store.get_product(alheio.id, user)
    end

    test "carrega as imagens", %{user: user} do
      p = product(user)
      {:ok, _} = Store.add_product_image(p, user, "#{p.id}/capa.png")

      assert {:ok, %{images: [image]}} = Store.get_product(p.id, user)
      assert image.path == "#{p.id}/capa.png"
    end
  end

  describe "add_product_image/3" do
    test "recusa dono errado", %{user: user, other: other} do
      p = product(user)
      assert {:error, :unauthorized} = Store.add_product_image(p, other, "x.png")
    end

    test "empilha na próxima posição", %{user: user} do
      p = product(user)
      {:ok, _} = Store.add_product_image(p, user, "a.png")
      {:ok, p} = Store.get_product(p.id, user)
      {:ok, _} = Store.add_product_image(p, user, "b.png")

      {:ok, p} = Store.get_product(p.id, user)
      assert [%{path: "a.png", position: 0}, %{path: "b.png", position: 1}] = p.images
    end
  end

  describe "redeem_product/2" do
    test "debita a carteira e registra o resgate quando há saldo", %{user: user} do
      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ganhar pontos", store_points: 100})

      {:ok, _} = Priorities.complete_activity(activity, user)

      p = product(user, %{price: 40})

      assert {:ok, redemption} = Store.redeem_product(p, user)
      assert redemption.price == 40
      assert Priorities.wallet_balance(user) == 60

      assert Enum.any?(
               Priorities.list_wallet_entries(user),
               &(&1.source == :redemption and &1.source_id == redemption.id and &1.amount == -40)
             )
    end

    test "recusa e não debita quando o saldo não cobre o preço", %{user: user} do
      p = product(user, %{price: 500})

      assert {:error, :insufficient_balance} = Store.redeem_product(p, user)
      assert Priorities.wallet_balance(user) == 0
      assert Priorities.list_wallet_entries(user) == []
    end
  end
end
