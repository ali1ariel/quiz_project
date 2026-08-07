defmodule QuizProject.AdaptiveStudy.StudyMaterial do
  @moduledoc """
  Material de estudo enviado pelo usuário e decomposto em Mapa Mental Atômico.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "study_materials"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :title, :raw_content, :summary, :mindmap_tree, :key_concepts, :status]
    end

    update :update do
      accept [:title, :summary, :mindmap_tree, :key_concepts, :status]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :raw_content, :string do
      allow_nil? false
      default ""
    end

    attribute :summary, :string do
      default ""
    end

    attribute :mindmap_tree, :map do
      allow_nil? false
      default %{}
    end

    attribute :key_concepts, :map do
      allow_nil? false
      default %{}
    end

    attribute :status, :string do
      allow_nil? false
      default "draft"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end
end
