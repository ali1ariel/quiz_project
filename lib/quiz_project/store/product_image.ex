defmodule QuizProject.Store.ProductImage do
  @moduledoc """
  Uma imagem de um produto da Wish Store. Várias por produto, ordenadas por
  `position` — a de posição 0 é a capa exibida na listagem e no detalhe
  (`QuizProject.Store.Product`). Só o caminho relativo em disco fica aqui; os
  bytes vivem fora do Postgres, em `QuizProject.Store.ImageStore`.
  """
  use Ash.Resource,
    domain: QuizProject.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "store_product_images"
    repo QuizProject.Repo

    references do
      reference :product, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:product_id, :path, :position]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :product_id, :uuid do
      allow_nil? false
    end

    attribute :path, :string do
      allow_nil? false
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :product, QuizProject.Store.Product do
      allow_nil? false
    end
  end
end
