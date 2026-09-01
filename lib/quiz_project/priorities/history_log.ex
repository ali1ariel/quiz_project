defmodule QuizProject.Priorities.HistoryLog do
  @moduledoc """
  Entrada de histórico: um evento pontual acontecido com uma atividade,
  categoria ou prioridade (criada, movida de coluna, arquivada, tag mexida,
  checklist mexido, ...) — a base da seção "Logs do dia" do Calendário
  (`QuizProjectWeb.KanbanLive.Calendar`) e da aba "Histórico" do modal de
  atividade. Append-only, gravado por `QuizProject.Priorities` logo depois
  de cada mutação de negócio bem-sucedida — nunca por sync do Google, geração
  automática de instância de hábito, nem edição de progresso frequente
  (curso, percentual manual, campo customizado), pra não inundar o dia com
  ruído.

  Aponta pra exatamente uma entidade — `activity_id`, `category_id` ou
  `item_id`, nunca mais de um, mesmo padrão de `Activity.item_id`/`habit_id`
  (ver `validations` abaixo). `message` já vem pronto pra exibir, com o
  nome/título da entidade embutido no texto — por isso excluir a entidade
  referenciada não apaga o log: a referência só é limpa (`on_delete:
  :nilify`), o texto do evento continua de pé.

  `logical_date` é o dia (fuso de Brasília, ver `Clock`) em que o evento
  aconteceu de fato — não uma data de negócio da entidade em si (ex: a data
  marcada de um evento).
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  alias QuizProject.Priorities.Clock

  postgres do
    table "priority_history_logs"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :activity, on_delete: :nilify, on_update: :update
      reference :category, on_delete: :nilify, on_update: :update
      reference :item, on_delete: :nilify, on_update: :update
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:user_id, :activity_id, :category_id, :item_id, :message]

      validate fn changeset, _context ->
        target_count =
          Enum.count(
            [:activity_id, :category_id, :item_id],
            &Ash.Changeset.get_attribute(changeset, &1)
          )

        if target_count == 1 do
          :ok
        else
          {:error,
           field: :activity_id,
           message:
             "log precisa apontar pra exatamente uma entidade (atividade, categoria ou prioridade)"}
        end
      end

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :logical_date, Clock.today())
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :activity_id, :uuid
    attribute :category_id, :uuid
    attribute :item_id, :uuid

    attribute :message, :string do
      allow_nil? false
    end

    attribute :logical_date, :date do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    belongs_to :activity, QuizProject.Priorities.Activity
    belongs_to :category, QuizProject.Priorities.Category
    belongs_to :item, QuizProject.Priorities.Item
  end
end
