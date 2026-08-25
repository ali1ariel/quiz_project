defmodule QuizProject.Repo.Migrations.HabitExtendsItem do
  @moduledoc """
  Hábito deixa de ter `category_id` (opcional, só cor de raia) e passa a
  ter `item_id` (obrigatório) — vira sempre extensão de uma prioridade.
  Feito manualmente (não pelo `mix ash.codegen` puro) porque precisa
  preservar dados: hábitos existentes presos a uma categoria são
  reapontados pro item "Geral" dela (criando o item "Geral" pra categorias
  que ainda não têm um — mesma lógica de
  `QuizProject.Priorities.general_item_for_category/1`), antes da coluna
  antiga sumir e da nova virar `NOT NULL`.
  """
  use Ecto.Migration

  def up do
    alter table(:priority_habits) do
      add :item_id,
          references(:priority_items,
            column: :id,
            name: "priority_habits_item_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all,
            on_update: :update_all
          )
    end

    execute("""
    INSERT INTO priority_items (id, user_id, category_id, item_type, title, general, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), c.user_id, c.id, 'manual', c.name || ' - Geral', true, 0, now(), now()
    FROM priority_categories c
    WHERE NOT EXISTS (
      SELECT 1 FROM priority_items i WHERE i.category_id = c.id AND i.general = true
    )
    """)

    execute("""
    UPDATE priority_habits h
    SET item_id = i.id
    FROM priority_items i
    WHERE i.category_id = h.category_id AND i.general = true
    """)

    alter table(:priority_habits) do
      modify :item_id, :uuid, null: false
      remove :category_id
    end
  end

  def down do
    drop constraint(:priority_habits, "priority_habits_item_id_fkey")

    alter table(:priority_habits) do
      remove :item_id

      add :category_id,
          references(:priority_categories,
            column: :id,
            name: "priority_habits_category_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all,
            on_update: :update_all
          )
    end
  end
end
