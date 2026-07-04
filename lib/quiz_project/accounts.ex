defmodule QuizProject.Accounts do
  use Ash.Domain

  require Ash.Query

  alias QuizProject.Accounts.ApiToken

  @api_scopes ["quizzes:read", "quizzes:write", "quizzes:publish"]

  resources do
    resource QuizProject.Accounts.User do
      define :register_user, action: :register
      define :get_user_by_id, action: :read, get_by: [:id]
    end

    resource ApiToken
  end

  @doc "Emite um token de API. O valor puro é retornado somente nesta chamada."
  def issue_api_token(%{id: user_id}, attrs \\ %{}) do
    token = "quiz_" <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))

    token_attrs = %{
      user_id: user_id,
      name: Map.get(attrs, :name, "Integração API"),
      token_hash: hash_token(token),
      scopes: @api_scopes,
      expires_at: Map.get(attrs, :expires_at)
    }

    case ApiToken
         |> Ash.Changeset.for_create(:create, token_attrs, authorize?: false)
         |> Ash.create() do
      {:ok, record} -> {:ok, token, record}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Autentica um token Bearer e retorna seu usuário e registro."
  def authenticate_api_token("quiz_" <> _ = token) do
    result =
      ApiToken
      |> Ash.Query.filter(token_hash == ^hash_token(token))
      |> Ash.Query.load(:user)
      |> Ash.read_one(authorize?: false)

    case result do
      {:ok, %ApiToken{} = record} ->
        if expired?(record) do
          :error
        else
          _ = record |> Ash.Changeset.for_update(:touch, %{}, authorize?: false) |> Ash.update()
          {:ok, record.user, record}
        end

      _ ->
        :error
    end
  end

  def authenticate_api_token(_token), do: :error

  @doc "Revoga o token autenticado."
  def revoke_api_token(%ApiToken{user_id: user_id} = token, %{id: user_id}) do
    Ash.destroy(token, authorize?: false)
  end

  def revoke_api_token(_token, _user), do: {:error, :unauthorized}

  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  defp expired?(%ApiToken{expires_at: nil}), do: false

  defp expired?(%ApiToken{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end
end
