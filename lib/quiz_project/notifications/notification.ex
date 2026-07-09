defmodule QuizProject.Notifications.Notification do
  @moduledoc """
  Notificação persistente de um evento em background para um usuário logado
  (ex.: correção de tentativa concluída). Fica visível em todas as páginas
  autenticadas até o usuário dispensá-la ou abrir o link — navegar ou
  recarregar a página não a perde.
  """
  use Ash.Resource,
    domain: QuizProject.Notifications,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "notifications"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :title, :body, :path]
    end

    update :mark_read do
      change set_attribute(:read_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
    end

    attribute :body, :string

    # rota interna para onde a notificação leva ("clique aqui para ver…")
    attribute :path, :string do
      allow_nil? false
    end

    attribute :read_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end
end
