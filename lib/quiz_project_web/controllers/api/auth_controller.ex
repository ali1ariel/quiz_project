defmodule QuizProjectWeb.Api.AuthController do
  use QuizProjectWeb, :controller

  alias QuizProject.Accounts
  alias QuizProject.Accounts.User
  alias QuizProjectWeb.Api.Response

  def create(conn, %{"email" => email, "password" => password} = params) do
    with {:ok, user} <- User.authenticate(email, password),
         {:ok, raw_token, token} <-
           Accounts.issue_api_token(user, %{name: params["name"] || "Integração API"}) do
      Response.created(conn, %{
        id: token.id,
        name: token.name,
        token: raw_token,
        token_type: "Bearer",
        scopes: token.scopes,
        expires_at: token.expires_at
      })
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_credentials", message: "E-mail ou senha inválidos"}})
    end
  end

  def create(conn, _params) do
    Response.validation(conn, ["email e password são obrigatórios"])
  end

  def delete(conn, _params) do
    case Accounts.revoke_api_token(conn.assigns.api_token, conn.assigns.current_user) do
      :ok -> Response.no_content(conn)
      {:ok, _record} -> Response.no_content(conn)
      {:error, error} -> Response.render_error(conn, error)
    end
  end
end
