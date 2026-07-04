defmodule QuizProject.Accounts.ApiToken do
  @moduledoc """
  Credencial de longa duração usada exclusivamente pela API JSON.

  O valor apresentado ao cliente nunca é persistido. Apenas seu hash SHA-256
  é armazenado, permitindo revogação sem expor credenciais em repouso.
  """

  use Ash.Resource,
    domain: QuizProject.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "api_tokens"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :name, :token_hash, :scopes, :expires_at]
    end

    update :touch do
      accept []
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      default "Integração API"
    end

    attribute :token_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :scopes, {:array, :string} do
      allow_nil? false
    end

    attribute :last_used_at, :utc_datetime_usec
    attribute :expires_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_token_hash, [:token_hash]
  end
end
