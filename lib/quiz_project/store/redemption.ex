defmodule QuizProject.Store.Redemption do
  @moduledoc """
  Registro de um resgate: o usuário trocou pontos por um produto do
  catálogo. Append-only, como `QuizProject.Priorities.WalletEntry` — guarda
  o preço pago no momento do resgate (`price`), independente do produto
  mudar de preço ou ser removido depois. É o `source_id` do lançamento de
  débito correspondente na carteira (`source: :redemption`).

  `product_id` some se o produto for removido (`on_delete: :nilify`) — o
  resgate em si não deve desaparecer do histórico junto com o produto.
  """
  use Ash.Resource,
    domain: QuizProject.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "store_redemptions"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :product, on_delete: :nilify, on_update: :update
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:user_id, :product_id, :price]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :product_id, :uuid

    attribute :price, :integer do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    belongs_to :product, QuizProject.Store.Product
  end
end
