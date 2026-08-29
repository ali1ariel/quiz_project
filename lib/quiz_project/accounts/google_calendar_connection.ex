defmodule QuizProject.Accounts.GoogleCalendarConnection do
  @moduledoc """
  Conexão de um usuário com o Google Calendar: credenciais OAuth, o
  calendário secundário dedicado criado para ele, e o estado da
  sincronização bidirecional (cursor de leitura incremental e canal de
  push notifications).

  Um usuário tem no máximo uma conexão (`identity :unique_user`) — todo o
  fluxo assume um único calendário dedicado por usuário.
  """

  use Ash.Resource,
    domain: QuizProject.Accounts,
    data_layer: AshPostgres.DataLayer

  alias QuizProject.Accounts.EncryptedString

  postgres do
    table "google_calendar_connections"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :user_id,
        :google_account_email,
        :access_token,
        :refresh_token,
        :access_token_expires_at,
        :calendar_id
      ]
    end

    update :update_tokens do
      accept []
      require_atomic? false

      argument :access_token, :string, allow_nil?: false
      argument :refresh_token, :string
      argument :access_token_expires_at, :utc_datetime_usec, allow_nil?: false

      change set_attribute(:access_token, arg(:access_token))
      change set_attribute(:access_token_expires_at, arg(:access_token_expires_at))

      # Google só devolve refresh_token na primeira autorização (ou quando
      # `prompt=consent` força um novo) — omitido no refresh comum, então só
      # sobrescreve quando um valor novo veio.
      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :refresh_token) do
          nil ->
            changeset

          refresh_token ->
            Ash.Changeset.force_change_attribute(changeset, :refresh_token, refresh_token)
        end
      end
    end

    update :update_watch_channel do
      accept [:channel_id, :channel_token_hash, :channel_resource_id, :channel_expires_at]
    end

    update :update_sync_state do
      accept []
      require_atomic? false

      argument :sync_token, :string

      change set_attribute(:sync_token, arg(:sync_token))
      change set_attribute(:last_sync_error, nil)
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
    end

    update :record_sync_error do
      accept []
      require_atomic? false

      argument :error, :string, allow_nil?: false

      change set_attribute(:last_sync_error, arg(:error))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :google_account_email, :string do
      allow_nil? false
    end

    attribute :access_token, EncryptedString do
      allow_nil? false
      sensitive? true
    end

    attribute :refresh_token, EncryptedString do
      allow_nil? false
      sensitive? true
    end

    attribute :access_token_expires_at, :utc_datetime_usec do
      allow_nil? false
    end

    # Id do calendário secundário dedicado, criado na conexão inicial.
    attribute :calendar_id, :string do
      allow_nil? false
    end

    # Cursor de `events.list` para sincronização incremental (Google →
    # app). Ausente até a primeira leitura completa depois do `events.watch`.
    attribute :sync_token, :string

    # Estado do canal de push notifications (`events.watch`) — usado pelo
    # renovador periódico e pela verificação do webhook.
    attribute :channel_id, :string
    attribute :channel_token_hash, :string, sensitive?: true
    attribute :channel_resource_id, :string
    attribute :channel_expires_at, :utc_datetime_usec

    attribute :last_synced_at, :utc_datetime_usec
    attribute :last_sync_error, :string

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user, [:user_id]
    identity :unique_channel_id, [:channel_id]
  end
end
