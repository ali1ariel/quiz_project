defmodule QuizProject.Accounts.User do
  use Ash.Resource,
    domain: QuizProject.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read]

    create :register do
      accept [:email, :name]
      argument :password, :string, allow_nil?: false, sensitive?: true

      validate match(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "e-mail inválido"

      validate fn changeset, _ ->
        password = Ash.Changeset.get_argument(changeset, :password)

        if is_binary(password) and String.length(password) >= 8 do
          :ok
        else
          {:error, field: :password, message: "senha deve ter pelo menos 8 caracteres"}
        end
      end

      change fn changeset, _ ->
        case Ash.Changeset.get_argument(changeset, :password) do
          password when is_binary(password) ->
            Ash.Changeset.force_change_attribute(
              changeset,
              :hashed_password,
              Bcrypt.hash_pwd_salt(password)
            )

          _ ->
            changeset
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    timestamps()
  end

  relationships do
    has_many :api_tokens, QuizProject.Accounts.ApiToken
  end

  identities do
    identity :unique_email, [:email], message: "e-mail já cadastrado"
  end

  @doc """
  Autentica por e-mail e senha. Retorna `{:ok, user}` ou `:error`.
  """
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    require Ash.Query

    query =
      __MODULE__
      |> Ash.Query.filter(email == ^email)
      |> Ash.Query.limit(1)

    case Ash.read_one(query, authorize?: false) do
      {:ok, user} when not is_nil(user) ->
        if Bcrypt.verify_pass(password, user.hashed_password) do
          {:ok, user}
        else
          :error
        end

      _ ->
        Bcrypt.no_user_verify()
        :error
    end
  end

  def authenticate(_, _), do: :error
end
