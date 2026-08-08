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
      accept [
        :user_id,
        :title,
        :raw_content,
        :summary,
        :mindmap_tree,
        :key_concepts,
        :status,
        :format,
        :author
      ]
    end

    update :update do
      accept [
        :title,
        :summary,
        :mindmap_tree,
        :key_concepts,
        :status,
        :format,
        :author,
        :reader_css,
        :ingest_error
      ]

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

    # Livro em EPUB não usa esta coluna: os blocos são a única cópia do texto, e
    # o corrido é concatenação sob demanda. O tipo string do Ash trata `""` como
    # nulo por padrão, então `allow_empty?` é o que deixa o material de livro
    # existir sem uma segunda cópia de 1,2MB que ninguém lê.
    attribute :raw_content, :string do
      allow_nil? false
      default ""
      constraints allow_empty?: true
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

    # `text` para material colado ou arquivo simples; `epub` para livro
    # ingerido em capítulos e blocos. Material `epub` não usa `raw_content` —
    # o texto corrido, quando alguém precisa, é concatenação sob demanda.
    attribute :format, :atom do
      allow_nil? false
      default :text
      constraints one_of: ~w(text epub)a
    end

    attribute :author, :string

    # Folha de estilo da editora, já filtrada e escopada. Servida por rota
    # própria com cache longo, em vez de ir junto do HTML a cada navegação —
    # ela carrega as fontes embutidas do livro.
    attribute :reader_css, :string

    attribute :ingest_error, :string

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    has_many :chapters, QuizProject.AdaptiveStudy.Chapter do
      destination_attribute :material_id
      sort position: :asc
    end
  end
end
