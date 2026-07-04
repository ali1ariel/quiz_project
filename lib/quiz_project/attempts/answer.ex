defmodule QuizProject.Attempts.Answer do
  @moduledoc """
  Resposta de uma tentativa a uma questão.

  Estados persistidos: `:unanswered`, `:answered` e `:dont_know`. A marca
  "responder depois" (`marked_later`) é ortogonal ao estado. O fluxo de
  limpar/restaurar usa `cleared_backup`/`cleared_at`; a janela de 10 segundos
  para restaurar é controlada pela interface.

  Formato do `payload` por tipo de questão:

    * verdadeiro/falso — `%{"value" => true | false}`
    * única — `%{"option" => identity_key da alternativa}`
    * múltiplas — `%{"options" => [identity_keys]}`
    * discursiva — `%{"text" => "..."}`

  Alternativas são referenciadas pela identidade estável, o que mantém a
  resposta válida quando reaproveitada em outra versão.
  """
  use Ash.Resource,
    domain: QuizProject.Attempts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "answers"
    repo QuizProject.Repo

    references do
      reference :attempt, on_delete: :delete
      reference :question, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:attempt_id, :question_id, :state, :payload, :imported_from_previous]
    end

    update :save do
      accept [
        :state,
        :payload,
        :marked_later,
        :imported_from_previous,
        :cleared_backup,
        :cleared_at
      ]
    end

    update :set_grade do
      accept [:score, :ai_percent, :ai_feedback, :ai_reference, :ai_reference_generated]
      require_atomic? false

      change set_attribute(:graded_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      constraints one_of: [:unanswered, :answered, :dont_know]
      allow_nil? false
      default :unanswered
    end

    attribute :payload, :map

    attribute :marked_later, :boolean do
      allow_nil? false
      default false
    end

    attribute :imported_from_previous, :boolean do
      allow_nil? false
      default false
    end

    attribute :cleared_backup, :map
    attribute :cleared_at, :utc_datetime_usec

    attribute :score, :decimal
    attribute :ai_percent, :integer
    attribute :ai_feedback, :string
    attribute :ai_reference, :string

    attribute :ai_reference_generated, :boolean do
      allow_nil? false
      default false
    end

    attribute :graded_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :attempt, QuizProject.Attempts.Attempt do
      allow_nil? false
    end

    belongs_to :question, QuizProject.Quizzes.Question do
      allow_nil? false
    end
  end

  identities do
    identity :unique_question_per_attempt, [:attempt_id, :question_id]
  end
end
