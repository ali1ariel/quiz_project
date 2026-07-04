defmodule QuizProject.Quizzes.Question do
  @moduledoc """
  Questão de uma versão de quiz.

  `identity_key` é a identidade estável da questão entre versões: ao criar uma
  nova versão do quiz, as cópias mantêm a mesma chave. O reaproveitamento de
  respostas entre versões casa questões pela `identity_key` e compara o
  `compatibility_hash` (calculado na publicação) para decidir se a resposta
  anterior ainda é válida.
  """
  use Ash.Resource,
    domain: QuizProject.Quizzes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "questions"
    repo QuizProject.Repo

    references do
      reference :quiz_version, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :quiz_version_id,
        :identity_key,
        :position,
        :statement,
        :type,
        :allow_partial_credit,
        :true_false_answer,
        :editor_note,
        :weight,
        :annulled,
        :annulled_reason,
        :ai_tags,
        :compatibility_hash
      ]

      change fn changeset, _ ->
        case Ash.Changeset.get_attribute(changeset, :identity_key) do
          nil ->
            Ash.Changeset.force_change_attribute(changeset, :identity_key, Ash.UUID.generate())

          _ ->
            changeset
        end
      end
    end

    update :update do
      accept [
        :position,
        :statement,
        :type,
        :allow_partial_credit,
        :true_false_answer,
        :editor_note,
        :weight,
        :annulled,
        :annulled_reason
      ]

      require_atomic? false
    end

    update :set_publication_data do
      accept [:ai_tags, :compatibility_hash]
    end

    # Anula ou reverte a questão. A anulação é retroativa e aplicada a todas as
    # versões pela camada de domínio (`Quizzes.annul_across_versions/4`).
    update :set_annulment do
      argument :annulled, :boolean, allow_nil?: false
      argument :reason, :string
      require_atomic? false

      change fn changeset, _ ->
        annulled = Ash.Changeset.get_argument(changeset, :annulled)
        reason = if annulled, do: Ash.Changeset.get_argument(changeset, :reason)
        annulled_at = if annulled, do: DateTime.utc_now()

        changeset
        |> Ash.Changeset.force_change_attribute(:annulled, annulled)
        |> Ash.Changeset.force_change_attribute(:annulled_reason, reason)
        |> Ash.Changeset.force_change_attribute(:annulled_at, annulled_at)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :identity_key, :uuid do
      allow_nil? false
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    attribute :statement, :string do
      allow_nil? false
      default ""
    end

    attribute :type, QuizProject.Quizzes.QuestionType do
      allow_nil? false
      default :single
    end

    # Somente para :multiple — habilita nota parcial proporcional
    attribute :allow_partial_credit, :boolean do
      allow_nil? false
      default false
    end

    # Somente para :true_false
    attribute :true_false_answer, :boolean

    # Resposta de referência: explica a resposta esperada, aparece no
    # resultado e é a referência principal da correção por IA em discursivas
    attribute :editor_note, :string

    attribute :weight, :decimal

    attribute :annulled, :boolean do
      allow_nil? false
      default false
    end

    attribute :annulled_reason, :string
    attribute :annulled_at, :utc_datetime_usec

    # Tags internas geradas por IA na publicação; nunca exibidas no protótipo
    attribute :ai_tags, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :compatibility_hash, :string

    timestamps()
  end

  relationships do
    belongs_to :quiz_version, QuizProject.Quizzes.QuizVersion do
      allow_nil? false
    end

    has_many :options, QuizProject.Quizzes.Option do
      sort position: :asc
    end
  end
end
