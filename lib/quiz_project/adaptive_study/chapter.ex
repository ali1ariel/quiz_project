defmodule QuizProject.AdaptiveStudy.Chapter do
  @moduledoc """
  Capítulo do livro, na ordem que o spine do EPUB declara.

  É a unidade de carregamento do leitor: um livro tem milhares de blocos e a
  tela carrega um capítulo por vez.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "chapters"
    repo QuizProject.Repo

    references do
      reference :material, on_delete: :delete, on_update: :update, index?: true
    end

    custom_indexes do
      index [:material_id, :position], unique: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :material_id,
        :source_id,
        :href,
        :title,
        :position,
        :level,
        :kind,
        :block_count
      ]
    end

    update :update do
      accept [:title, :kind, :block_count]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :material_id, :uuid do
      allow_nil? false
    end

    # `idref` do spine. Junto do material identifica o capítulo entre
    # reingestões do mesmo arquivo.
    attribute :source_id, :string do
      allow_nil? false
      default ""
    end

    attribute :href, :string do
      allow_nil? false
      default ""
    end

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :position, :integer do
      allow_nil? false
    end

    attribute :level, :integer do
      allow_nil? false
      default 1
    end

    # `front_matter` | `body` | `back_matter`. Sem isso o leitor abre no aviso
    # de copyright e a IA processa a página de agradecimentos.
    attribute :kind, :atom do
      allow_nil? false
      default :body
      constraints one_of: ~w(front_matter body back_matter)a
    end

    attribute :block_count, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :material, QuizProject.AdaptiveStudy.StudyMaterial do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end

    has_many :blocks, QuizProject.AdaptiveStudy.Block do
      destination_attribute :chapter_id
    end
  end
end
