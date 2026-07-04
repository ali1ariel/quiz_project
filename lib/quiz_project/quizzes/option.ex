defmodule QuizProject.Quizzes.Option do
  @moduledoc """
  Alternativa de uma questão objetiva. `identity_key` é estável entre versões,
  permitindo que respostas reaproveitadas apontem para a mesma alternativa.
  """
  use Ash.Resource,
    domain: QuizProject.Quizzes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "options"
    repo QuizProject.Repo

    references do
      reference :question, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:question_id, :identity_key, :position, :text, :correct]

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
      accept [:position, :text, :correct]
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

    attribute :text, :string do
      allow_nil? false
      default ""
    end

    attribute :correct, :boolean do
      allow_nil? false
      default false
    end

    timestamps()
  end

  relationships do
    belongs_to :question, QuizProject.Quizzes.Question do
      allow_nil? false
    end
  end
end
