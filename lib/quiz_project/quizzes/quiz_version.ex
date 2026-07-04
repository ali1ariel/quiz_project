defmodule QuizProject.Quizzes.QuizVersion do
  @moduledoc """
  Uma versão de um quiz. Rascunhos são editáveis; versões publicadas são
  congeladas e nunca mudam (exceto anulação de questão, que é um ato
  administrativo permitido sobre versão publicada).

  Tentativas apontam sempre para a versão específica respondida.
  """
  use Ash.Resource,
    domain: QuizProject.Quizzes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "quiz_versions"
    repo QuizProject.Repo

    references do
      reference :quiz, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :quiz_id,
        :version_number,
        :name,
        :description,
        :total_points,
        :unequal_weights,
        :question_order_mode
      ]
    end

    update :update_draft do
      accept [:name, :description, :total_points, :unequal_weights, :question_order_mode]
      require_atomic? false

      validate fn changeset, _ ->
        if changeset.data.status == :draft do
          :ok
        else
          {:error, message: "somente rascunhos podem ser editados"}
        end
      end

      validate compare(:total_points, greater_than: 0), message: "nota total deve ser positiva"
    end

    update :set_changelog do
      accept [:changelog]
    end

    update :mark_published do
      accept [:changelog]
      require_atomic? false

      change set_attribute(:status, :published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer do
      allow_nil? false
      default 1
    end

    attribute :name, :string do
      public? true
      default ""
    end

    attribute :description, :string do
      public? true
      default ""
    end

    attribute :total_points, :decimal do
      allow_nil? false
      default Decimal.new(100)
    end

    attribute :unequal_weights, :boolean do
      allow_nil? false
      default false
    end

    attribute :question_order_mode, QuizProject.Quizzes.OrderMode do
      allow_nil? false
      default :fixed
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :published]
      allow_nil? false
      default :draft
    end

    attribute :published_at, :utc_datetime_usec

    attribute :changelog, {:array, :string} do
      allow_nil? false
      default []
    end

    timestamps()
  end

  relationships do
    belongs_to :quiz, QuizProject.Quizzes.Quiz do
      allow_nil? false
    end

    has_many :questions, QuizProject.Quizzes.Question do
      sort position: :asc
    end
  end

  identities do
    identity :unique_version_per_quiz, [:quiz_id, :version_number]
  end
end
