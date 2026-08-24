defmodule QuizProject.Priorities.Activity do
  @moduledoc """
  Atividade: o que entra no kanban do dia. Pode nascer presa a um `Item`
  (`item_id` presente) ou solta (`item_id` nulo — "captura solta", a peça
  ainda não categorizada).

  `status` e `flow` são dois eixos independentes de propósito: `status` é o
  desfecho (pendente/concluída/não cumprida/descartada), `flow` é a posição
  no kanban (todo/fazendo/feito). Nenhuma action genérica escreve os dois —
  cada transição de negócio (`:start`, `:complete`, `:discard`, ...) é quem
  garante que ficam consistentes entre si.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_activities"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :item, on_delete: :nilify, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :item_id, :title, :notes, :logical_date, :position]
    end

    update :update do
      accept [:title, :notes]
    end

    update :reposition do
      accept [:position]
    end

    update :assign_item do
      accept []
      argument :item_id, :uuid, allow_nil?: false
      change set_attribute(:item_id, arg(:item_id))
    end

    update :start do
      accept []

      validate attribute_equals(:status, :pendente),
        message: "só é possível iniciar uma atividade pendente"

      change set_attribute(:flow, :fazendo)
    end

    update :back_to_todo do
      accept []

      validate attribute_equals(:flow, :fazendo),
        message: "só é possível voltar pra fila uma atividade em andamento"

      change set_attribute(:flow, :todo)
    end

    update :complete do
      accept []
      change set_attribute(:status, :concluida)
      change set_attribute(:flow, :feito)
    end

    update :mark_not_done do
      accept []
      change set_attribute(:status, :nao_cumprida)
      change set_attribute(:flow, :feito)
    end

    update :discard do
      accept []
      change set_attribute(:status, :descartada)
      change set_attribute(:flow, :feito)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    # Ausente = captura solta.
    attribute :item_id, :uuid

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :notes, :string do
      default ""
    end

    attribute :status, :atom do
      allow_nil? false
      default :pendente
      constraints one_of: ~w(pendente concluida nao_cumprida descartada)a
    end

    attribute :flow, :atom do
      allow_nil? false
      default :todo
      constraints one_of: ~w(todo fazendo feito)a
    end

    # Dia lógico da atividade, gravado na criação — nunca recalculado a
    # partir do timestamp depois, pra não mudar de coluna sozinha.
    attribute :logical_date, :date do
      allow_nil? false
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    belongs_to :item, QuizProject.Priorities.Item do
      attribute_writable? true
    end
  end
end
