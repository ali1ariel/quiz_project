defmodule QuizProject.Priorities.HabitConfig do
  @moduledoc """
  Configuração de recorrência de um item do tipo `:habit` — 1:1 com `Item`.
  `:daily` é o padrão pré-marcado na criação; `:weekly`/`:monthly` usam
  `weekdays`/`month_days` respectivamente. Ver
  `QuizProject.Priorities.HabitRecurrence.due_on?/2` pra saber se um dia é
  devido.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_habit_configs"
    repo QuizProject.Repo

    references do
      reference :item, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:item_id, :frequency, :weekdays, :month_days]
    end

    update :update do
      accept [:frequency, :weekdays, :month_days]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :frequency, :atom do
      allow_nil? false
      default :daily
      constraints one_of: ~w(daily weekly monthly)a
    end

    # 1(segunda)..7(domingo), igual `Date.day_of_week/1` — usado só quando
    # frequency == :weekly.
    attribute :weekdays, {:array, :integer} do
      allow_nil? false
      default []
    end

    # 1..31 — usado só quando frequency == :monthly.
    attribute :month_days, {:array, :integer} do
      allow_nil? false
      default []
    end

    timestamps()
  end

  relationships do
    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end
  end

  identities do
    identity :item_id, [:item_id]
  end
end
