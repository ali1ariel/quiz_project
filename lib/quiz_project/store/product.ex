defmodule QuizProject.Store.Product do
  @moduledoc """
  Um produto do catálogo da Wish Store: recompensa cadastrada pelo próprio
  usuário e resgatável com os pontos da carteira dele
  (`QuizProject.Priorities.wallet_balance/1`). Não há catálogo global nem
  conceito de administrador — quem cadastra é quem resgata, mesma regra de
  posse do resto do app (ver `QuizProject.Store.authorize_owner/2`).

  As imagens não ficam aqui: `has_many :images` aponta para
  `ProductImage`, uma por arquivo em disco (ver `QuizProject.Store.ImageStore`),
  ordenadas por `position` — a de posição 0 é a capa exibida na listagem.
  """
  use Ash.Resource,
    domain: QuizProject.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "store_products"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :name, :description, :price]
    end

    update :update do
      accept [:name, :description, :price]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 120
    end

    attribute :description, :string do
      allow_nil? false
      constraints max_length: 2000
    end

    attribute :price, :integer do
      allow_nil? false
      constraints min: 1
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    has_many :images, QuizProject.Store.ProductImage do
      sort position: :asc
    end
  end
end
