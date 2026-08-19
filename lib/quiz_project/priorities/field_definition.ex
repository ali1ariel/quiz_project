defmodule QuizProject.Priorities.FieldDefinition do
  @moduledoc """
  Campo customizado definido pelo usuário (taxonomia livre), global: uma vez
  criado, fica disponível para preencher em qualquer item de qualquer categoria.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_field_definitions"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :name, :field_type, :select_options, :position]
    end

    update :update do
      accept [:name, :select_options, :position]
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

    attribute :field_type, :atom do
      allow_nil? false
      constraints one_of: ~w(text select number)a
    end

    # Só usado quando `field_type == :select`; vazio nos demais tipos.
    attribute :select_options, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end
end
