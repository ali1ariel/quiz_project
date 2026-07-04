defmodule QuizProjectWeb.AuthController do
  use QuizProjectWeb, :controller

  alias QuizProject.Accounts
  alias QuizProject.Accounts.User
  alias QuizProjectWeb.UserAuth

  def register_form(conn, _params) do
    render(conn, :register, error: nil, email: "", name: "")
  end

  def register(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    case Accounts.register_user(%{email: email, name: params["name"], password: password},
           authorize?: false
         ) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Conta criada com sucesso!")
        |> UserAuth.log_in_user(user)

      {:error, error} ->
        render(conn, :register,
          error: humanize_errors(error),
          email: email,
          name: params["name"] || ""
        )
    end
  end

  def login_form(conn, _params) do
    render(conn, :login, error: nil, email: "")
  end

  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case User.authenticate(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Bem-vindo de volta!")
        |> UserAuth.log_in_user(user)

      :error ->
        render(conn, :login, error: "E-mail ou senha inválidos.", email: email)
    end
  end

  def logout(conn, _params) do
    conn
    |> put_flash(:info, "Você saiu da sua conta.")
    |> UserAuth.log_out_user()
  end

  defp humanize_errors(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(fn
      %{message: message} when is_binary(message) -> message
      other -> Exception.message(other)
    end)
    |> Enum.uniq()
    |> Enum.join(". ")
  end

  defp humanize_errors(error), do: Exception.message(error)
end
