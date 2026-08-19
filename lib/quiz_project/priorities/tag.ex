defmodule QuizProject.Priorities.Tag do
  @moduledoc """
  Etiqueta livre criada pelo usuário, reaproveitável em qualquer item.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_tags"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :name]

      # `upsert_fields` precisa de pelo menos uma coluna: com a lista vazia o
      # Postgres gera `ON CONFLICT DO NOTHING`, que não devolve a linha
      # existente via `RETURNING` — `updated_at` é o campo inofensivo que
      # garante o find-or-create devolver a tag já existente.
      upsert? true
      upsert_identity :user_name
      upsert_fields [:updated_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :name, :string do
      allow_nil? false
      default ""
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :user_name, [:user_id, :name]
  end
end
