defmodule QuizProject.Repo.Migrations.DropHabitConfigs do
  @moduledoc """
  Remove `priority_habit_configs` — substituído por `priority_habits`
  (ver `20260824200946_add_habit_and_activity_habit_id.exs`), já que hábito
  deixou de ser um `item_type` de `Item` e passou a ser seu próprio resource,
  independente de prioridade. Escrita à mão porque não sobrou nenhum resource
  vivo pro `ash_postgres` gerar o drop sozinho a partir do snapshot órfão.
  """

  use Ecto.Migration

  def up do
    drop constraint(:priority_habit_configs, "priority_habit_configs_item_id_fkey")

    drop_if_exists unique_index(:priority_habit_configs, [:item_id],
                     name: "priority_habit_configs_item_id_index"
                   )

    drop table(:priority_habit_configs)
  end

  def down do
    create table(:priority_habit_configs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :frequency, :text, null: false, default: "daily"
      add :weekdays, {:array, :bigint}, null: false, default: []
      add :month_days, {:array, :bigint}, null: false, default: []

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :item_id,
          references(:priority_items,
            column: :id,
            name: "priority_habit_configs_item_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all,
            on_update: :update_all
          ),
          null: false
    end

    create unique_index(:priority_habit_configs, [:item_id],
             name: "priority_habit_configs_item_id_index"
           )
  end
end
