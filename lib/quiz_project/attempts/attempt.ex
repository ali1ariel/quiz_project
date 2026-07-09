defmodule QuizProject.Attempts.Attempt do
  @moduledoc """
  Uma tentativa de resposta a uma versão específica de quiz.

  A tentativa pertence a um usuário logado (`user_id`) ou a um token de
  sessão anônimo (`participant_token`). Se o participante logar durante a
  resposta, as tentativas do token são adotadas pela conta.

  `question_order` é a lista fixa de ids de questão definida no início da
  tentativa — a ordem nunca muda entre renderizações.

  `display_identity` é como o participante escolheu se identificar. O dono
  do quiz vê apenas isso, nunca dados da conta.
  """
  use Ash.Resource,
    domain: QuizProject.Attempts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "attempts"
    repo QuizProject.Repo

    references do
      reference :quiz_version, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      accept [:quiz_version_id, :user_id, :participant_token, :display_identity, :question_order]

      change set_attribute(:started_at, &DateTime.utc_now/0)

      validate present(:display_identity), message: "informe como prefere se identificar"
    end

    update :adopt do
      accept [:user_id]
    end

    # Entrega da tentativa: sai de :in_progress e entra na fila de correção
    # em background. O participante não espera a correção — é notificado via
    # PubSub quando ela termina (ver QuizProject.Attempts.Notifier).
    update :start_processing do
      change set_attribute(:status, :processing)
    end

    update :finish do
      accept [:score, :max_score, :percent]
      require_atomic? false

      change set_attribute(:status, :finished)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    # Recalcula a nota sem mexer em status/finished_at — usado na anulação
    # retroativa de uma questão sobre tentativas já finalizadas.
    update :set_totals do
      accept [:score, :max_score, :percent]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :display_identity, :string do
      allow_nil? false
    end

    attribute :participant_token, :string

    attribute :status, :atom do
      constraints one_of: [:in_progress, :processing, :finished]
      allow_nil? false
      default :in_progress
    end

    attribute :question_order, {:array, :uuid} do
      allow_nil? false
      default []
    end

    attribute :started_at, :utc_datetime_usec
    attribute :finished_at, :utc_datetime_usec

    attribute :score, :decimal
    attribute :max_score, :decimal
    attribute :percent, :decimal

    timestamps()
  end

  relationships do
    belongs_to :quiz_version, QuizProject.Quizzes.QuizVersion do
      allow_nil? false
    end

    belongs_to :user, QuizProject.Accounts.User

    has_many :answers, QuizProject.Attempts.Answer
  end
end
