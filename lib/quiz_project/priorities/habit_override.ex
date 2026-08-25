defmodule QuizProject.Priorities.HabitOverride do
  @moduledoc """
  Exceção de um hábito numa data específica — "pular esse dia" e/ou
  "título/nota só desse dia", sem mexer na regra (`Habit.frequency` etc)
  nem nos outros dias. Só existe pra dias que ainda não viraram `Activity`
  (dias futuros, editados pela tela "Próximos dias" via `HabitModal`); o
  dia de hoje já tem uma `Activity` de verdade, editável direto — não
  precisa de exceção.

  Uma linha por (`habit_id`, `date`) — `create` é upsert (mesmo padrão de
  `Priorities.Tag`), então salvar de novo pra uma data que já tinha
  exceção só atualiza a linha em vez de duplicar.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_habit_overrides"
    repo QuizProject.Repo

    references do
      reference :habit, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:habit_id, :date, :skipped, :title, :notes]

      upsert? true
      upsert_identity :habit_date
      upsert_fields [:skipped, :title, :notes]
    end

    update :update do
      accept [:skipped, :title, :notes]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :date, :date do
      allow_nil? false
    end

    attribute :skipped, :boolean do
      allow_nil? false
      default false
    end

    # Título/nota só desse dia — `nil` = usa o do `Habit`.
    attribute :title, :string
    attribute :notes, :string

    timestamps()
  end

  relationships do
    belongs_to :habit, QuizProject.Priorities.Habit do
      allow_nil? false
    end
  end

  identities do
    identity :habit_date, [:habit_id, :date]
  end
end
