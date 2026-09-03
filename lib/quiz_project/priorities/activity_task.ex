defmodule QuizProject.Priorities.ActivityTask do
  @moduledoc """
  Subitem de checklist de uma atividade — mesmo papel que `ItemTask` tem
  pra um item do tipo `:checklist`, só que preso a uma `Activity`.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_activity_tasks"
    repo QuizProject.Repo

    references do
      reference :activity, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:activity_id, :title, :position, :store_points]
    end

    update :update do
      accept [:title, :done, :position, :store_points]
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

    attribute :store_points, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :activity, QuizProject.Priorities.Activity do
      allow_nil? false
    end
  end
end
