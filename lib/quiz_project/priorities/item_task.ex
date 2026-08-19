defmodule QuizProject.Priorities.ItemTask do
  @moduledoc """
  Subtarefa de um item do tipo `:checklist`.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_item_tasks"
    repo QuizProject.Repo

    references do
      reference :item, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:item_id, :title, :position]
    end

    update :update do
      accept [:title, :done, :position]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :done, :boolean do
      allow_nil? false
      default false
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end
  end
end
