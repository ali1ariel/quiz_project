defmodule QuizProject.Priorities.Category do
  @moduledoc """
  Agrupador de itens de Prioridades, ex: "Livros", "Hábitos".
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_categories"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :name, :position, :default_item_store_points]
    end

    update :update do
      accept [:name, :default_item_store_points]
    end

    update :reposition do
      accept [:position]
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

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    # `nil` (o padrão) significa "usa a pontuação padrão de prioridade das
    # Configurações" (`Priorities.get_point_defaults/1`) — só ganha um número
    # próprio quem for sobrescrever isso para os itens criados aqui dentro.
    attribute :default_item_store_points, :integer do
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    has_many :items, QuizProject.Priorities.Item do
      destination_attribute :category_id
      sort position: :asc
    end
  end
end
