defmodule QuizProjectWeb.ApiAuth do
  @moduledoc "Autenticação Bearer para os endpoints JSON da API."

  import Plug.Conn

  alias QuizProject.Accounts

  def init(opts), do: opts
  def call(conn, opts), do: fetch_api_user(conn, opts)

  def fetch_api_user(conn, _opts) do
    with {:ok, raw_token} <- bearer_token(conn),
         {:ok, user, token} <- Accounts.authenticate_api_token(raw_token) do
      conn
      |> assign(:current_user, user)
      |> assign(:api_token, token)
    else
      _ -> unauthorized(conn)
    end
  end

  def require_scope(conn, scope) when is_binary(scope) do
    if scope in conn.assigns.api_token.scopes do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        :forbidden,
        Jason.encode!(%{error: %{code: "insufficient_scope", required_scope: scope}})
      )
      |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [header] ->
        case String.split(header, " ", parts: 2) do
          [scheme, token] when byte_size(token) > 0 ->
            if String.downcase(scheme) == "bearer", do: {:ok, token}, else: :error

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="quiz-api"))
    |> put_resp_content_type("application/json")
    |> send_resp(
      :unauthorized,
      Jason.encode!(%{error: %{code: "unauthorized", message: "Token ausente ou inválido"}})
    )
    |> halt()
  end
end
