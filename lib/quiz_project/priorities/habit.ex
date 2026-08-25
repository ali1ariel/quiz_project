defmodule QuizProject.Priorities.Habit do
  @moduledoc """
  Hábito recorrente: um tipo de atividade, sempre extensão de uma
  prioridade (`Item`) — nunca solto. `item_id` é obrigatório; quando o
  usuário anexa o hábito só a uma categoria (não a uma prioridade
  específica), `item_id` aponta pro item "Geral" dela (ver
  `Priorities.general_item_for_category/1`). Gera `Activity` diárias
  devidas conforme `frequency`/`weekdays`/`month_days`. Apagar o item
  cascade-apaga o hábito (`on_delete: :delete`), mesmo padrão de
  `Item`/categoria.

  `:daily` é o padrão pré-marcado na criação; `:weekly`/`:monthly` usam
  `weekdays`/`month_days` respectivamente. Ver
  `QuizProject.Priorities.HabitRecurrence.due_on?/3` pra saber se um dia é
  devido.

  `starts_on`/`ends_on` delimitam quando a regra atual vale — usados só por
  `Priorities.change_habit_frequency_from/4` (a mudança "essa e as
  próximas": o hábito atual ganha `ends_on` no dia anterior à mudança, e um
  hábito novo nasce com `starts_on` na data da mudança, com a regra nova).
  Fora desse fluxo ficam `nil` (sem limite) pra sempre.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_habits"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :item, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :item_id, :title, :frequency, :weekdays, :month_days, :starts_on]
    end

    update :update do
      accept [:title, :frequency, :weekdays, :month_days, :ends_on]
    end

    update :archive do
      accept []
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :unarchive do
      accept []
      change set_attribute(:archived_at, nil)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :item_id, :uuid do
      allow_nil? false
    end

    attribute :title, :string do
      allow_nil? false
      default ""
    end

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

    attribute :archived_at, :utc_datetime_usec

    # `nil` = sem limite. Ver moduledoc.
    attribute :starts_on, :date
    attribute :ends_on, :date

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end
  end
end
