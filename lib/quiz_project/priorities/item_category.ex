defmodule QuizProject.Priorities.ItemCategory do
  @moduledoc """
  Associação entre um item e uma categoria secundária (além da principal,
  guardada em `Item.category_id`). Tabela de junção de `Item.secondary_categories`.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_item_categories"
    repo QuizProject.Repo

    references do
      reference :item, on_delete: :delete, on_update: :update
      reference :category, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:item_id, :category_id]

      # Lista vazia de `upsert_fields` viraria `ON CONFLICT DO NOTHING`, que não
      # devolve a linha via `RETURNING` (ver `Tag.create/1`) — daí o `updated_at`.
      upsert? true
      upsert_identity :item_category
      upsert_fields [:updated_at]
    end
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end

    belongs_to :category, QuizProject.Priorities.Category do
      allow_nil? false
    end
  end

  identities do
    identity :item_category, [:item_id, :category_id]
  end
end
