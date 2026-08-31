defmodule QuizProject.Priorities.ActivityLog do
  @moduledoc """
  Entrada de histórico: um evento pontual acontecido com uma atividade
  (criada, movida de coluna, resolvida, checklist mexido, ...) — a base da
  seção "Logs do dia" do Calendário (`QuizProjectWeb.KanbanLive.Calendar`).
  Append-only, gravado por `QuizProject.Priorities` logo depois de cada
  mutação de negócio bem-sucedida — nunca por sync do Google nem geração
  automática de instância de hábito, pra não inundar o dia com ruído.

  `message` já vem pronto pra exibir (com o título da atividade embutido no
  texto) — a atividade pode ser renomeada depois, sem isso um log antigo
  mudaria de texto sozinho.

  `logical_date` é o dia (fuso de Brasília, ver `Clock`) em que o evento
  aconteceu de fato — não o `logical_date`/`resolved_date` da atividade em
  si, que podem apontar pra outro dia (ex: corrigir hoje o desfecho de uma
  atividade de semana passada gera um log em hoje, não lá atrás).
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  alias QuizProject.Priorities.Clock

  postgres do
    table "priority_activity_logs"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :activity, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:user_id, :activity_id, :message]

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

    attribute :activity_id, :uuid do
      allow_nil? false
    end

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

    belongs_to :activity, QuizProject.Priorities.Activity do
      allow_nil? false
    end
  end
end
