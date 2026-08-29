defmodule QuizProject.Priorities.Activity do
  @moduledoc """
  Atividade: o que entra no kanban do dia. Pode nascer presa a um `Item`
  (`item_id` presente), ser uma instância de `Habit` (`habit_id` presente) ou
  solta (nenhum dos dois — "captura solta", a peça ainda não categorizada).
  `item_id` e `habit_id` nunca coexistem (ver `validations` abaixo).

  `status` e `flow` são dois eixos independentes de propósito: `status` é o
  desfecho (pendente/concluída/não cumprida/descartada), `flow` é a posição
  no kanban (todo/fazendo/feito). Nenhuma action genérica escreve os dois —
  cada transição de negócio (`:start`, `:complete`, `:discard`, ...) é quem
  garante que ficam consistentes entre si.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  alias QuizProject.Priorities.Clock

  postgres do
    table "priority_activities"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :item, on_delete: :nilify, on_update: :update
      reference :habit, on_delete: :nilify, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :item_id, :habit_id, :title, :notes, :logical_date, :position]

      validate fn changeset, _context ->
        item_id = Ash.Changeset.get_attribute(changeset, :item_id)
        habit_id = Ash.Changeset.get_attribute(changeset, :habit_id)

        if item_id && habit_id do
          {:error,
           field: :habit_id,
           message: "atividade não pode estar presa a um item e a um hábito ao mesmo tempo"}
        else
          :ok
        end
      end
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
      require_atomic? false
      change set_attribute(:status, :concluida)
      change set_attribute(:flow, :feito)

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :resolved_date, Clock.today())
      end
    end

    update :mark_not_done do
      accept []
      require_atomic? false
      change set_attribute(:status, :nao_cumprida)
      change set_attribute(:flow, :feito)

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :resolved_date, Clock.today())
      end
    end

    update :discard do
      accept []
      require_atomic? false
      change set_attribute(:status, :descartada)
      change set_attribute(:flow, :feito)

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :resolved_date, Clock.today())
      end
    end

    # Corrige o desfecho de uma atividade já resolvida sem reabri-la nem
    # mexer em `resolved_date` — usada só pelo Histórico (calendário de dias
    # anteriores), que é consulta e não pode arrastar a atividade pro dia da
    # correção (diferente de `:complete`/`:mark_not_done`, que são a
    # resolução em si e por isso gravam `resolved_date` como hoje).
    update :correct_status do
      accept []

      argument :status, :atom,
        allow_nil?: false,
        constraints: [one_of: [:concluida, :nao_cumprida]]

      validate attribute_equals(:flow, :feito),
        message: "só é possível corrigir o desfecho de uma atividade já resolvida"

      change set_attribute(:status, arg(:status))
    end

    update :reopen do
      accept []

      validate attribute_equals(:flow, :feito),
        message: "só é possível reabrir uma atividade já resolvida"

      change set_attribute(:status, :pendente)
      change set_attribute(:flow, :todo)
      change set_attribute(:resolved_date, nil)
    end

    # Adiar: some da Tela do dia até `until` (exclusive de hoje, inclusive
    # de `until`) sem mudar `logical_date` nem `status`/`flow` — não é uma
    # resolução, só uma pausa. Só faz sentido pra atividade presa a item
    # (não hábito, que já tem sua própria noção de "dia devido").
    update :snooze do
      accept []
      require_atomic? false
      argument :until, :date, allow_nil?: false

      validate absent(:habit_id),
        message: "hábito não pode ser adiado, só atividade presa a item"

      validate fn changeset, _context ->
        until = Ash.Changeset.get_argument(changeset, :until)

        if Date.compare(until, Clock.today()) == :gt do
          :ok
        else
          {:error, field: :until, message: "a data precisa ser depois de hoje"}
        end
      end

      change set_attribute(:snoozed_until, arg(:until))
    end

    update :clear_snooze do
      accept []
      change set_attribute(:snoozed_until, nil)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    # Ausente (junto com habit_id) = captura solta.
    attribute :item_id, :uuid

    # Presente = esta atividade é uma instância diária de um hábito.
    attribute :habit_id, :uuid

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

    # Dia em que a atividade foi resolvida (concluída/não cumprida/descartada),
    # gravado pelas actions de resolução e limpo por `:reopen`. Separado de
    # `logical_date` porque atividade presa a item não expira mais sozinha —
    # sem isso não daria pra saber o que foi resolvido hoje pra coluna "Feito".
    attribute :resolved_date, :date

    # Presente = atividade adiada, some da Tela do dia até essa data (ver
    # `Priorities.list_today_activities/1`). Só faz sentido pra atividade
    # presa a item — hábito já tem sua própria noção de dia devido.
    attribute :snoozed_until, :date

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

    belongs_to :habit, QuizProject.Priorities.Habit do
      attribute_writable? true
    end
  end
end
