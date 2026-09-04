defmodule QuizProject.Priorities.PointDefaults do
  @moduledoc """
  Pontuação padrão por tipo de elemento (atividade, subitem de checklist,
  prioridade e hábito) — pré-preenche o campo "Pontos" sempre que um deles
  é criado, em vez de sempre começar do zero. Uma linha por usuário, mesmo
  padrão de `QuizProject.AdaptiveStudy.ReadingPreference`.

  Uma prioridade (`Item.default_activity_store_points`) pode sobrescrever
  `activity_points` só para as atividades geradas dentro dela; atividades
  capturadas direto do Kanban (sem prioridade) sempre usam `activity_points`
  daqui, nunca a sobrescrita de um item — ver `Priorities.get_point_defaults/1`.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_point_defaults"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [:user_id, :activity_points, :activity_task_points, :item_points, :habit_points]

      upsert? true
      upsert_identity :unique_user

      upsert_fields [
        :activity_points,
        :activity_task_points,
        :item_points,
        :habit_points,
        :updated_at
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :activity_points, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :activity_task_points, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :item_points, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    attribute :habit_points, :integer do
      allow_nil? false
      default 0
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
