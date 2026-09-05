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
      accept [:user_id, :name, :description, :price, :link_url, :link_text]
    end

    update :update do
      accept [:name, :description, :price, :link_url, :link_text]
    end
  end

  validations do
    validate present(:link_url),
      where: [present(:link_text)],
      message: "obrigatório quando o texto do link é informado"

    validate present(:link_text),
      where: [present(:link_url)],
      message: "obrigatório quando a URL do link é informada"
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

    attribute :link_url, :string do
      allow_nil? true
      constraints max_length: 2048
    end

    attribute :link_text, :string do
      allow_nil? true
      constraints max_length: 120
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
