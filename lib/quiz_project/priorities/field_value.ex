defmodule QuizProject.Priorities.FieldValue do
  @moduledoc """
  Valor de um campo customizado num item específico. `value_text` guarda o
  valor de campos `:text`/`:select`; `value_number` guarda o de `:number` — só
  um dos dois é preenchido, a depender de `FieldDefinition.field_type`.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_field_values"
    repo QuizProject.Repo

    references do
      reference :item, on_delete: :delete, on_update: :update
      reference :field_definition, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      accept [:item_id, :field_definition_id, :value_text, :value_number]

      upsert? true
      upsert_identity :item_field
      upsert_fields [:value_text, :value_number, :updated_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :value_text, :string
    attribute :value_number, :float

    timestamps()
  end

  relationships do
    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end

    belongs_to :field_definition, QuizProject.Priorities.FieldDefinition do
      allow_nil? false
    end
  end

  identities do
    identity :item_field, [:item_id, :field_definition_id]
  end
end
