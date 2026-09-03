defmodule QuizProject.Priorities.WalletEntry do
  @moduledoc """
  Lançamento na carteira de pontos do usuário: um crédito (conclusão de
  atividade, subitem de checklist ou prioridade atingindo 100%) ou um
  estorno (desfazer essa conclusão). Append-only — o saldo é sempre a soma
  de `amount` do usuário (`QuizProject.Priorities.wallet_balance/1`), nunca
  um campo à parte, pra não divergir do histórico.

  `source`/`source_id` apontam pra quem gerou o lançamento (`Activity`,
  `ActivityTask` ou `Item`) sem FK de verdade — são três tabelas possíveis
  pra uma coluna só, e apagar a origem não deve apagar o lançamento (o
  extrato continua de pé mesmo que a atividade não exista mais).
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_wallet_entries"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:user_id, :amount, :source, :source_id, :description]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :amount, :integer do
      allow_nil? false
    end

    attribute :source, :atom do
      allow_nil? false
      constraints one_of: ~w(activity activity_task item)a
    end

    attribute :source_id, :uuid do
      allow_nil? false
    end

    attribute :description, :string do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end
end
