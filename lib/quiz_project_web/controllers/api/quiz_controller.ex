defmodule QuizProjectWeb.Api.QuizController do
  use QuizProjectWeb, :controller

  alias QuizProject.Quizzes
  alias QuizProjectWeb.Api.{Params, Response, Serializer}
  alias QuizProjectWeb.ApiAuth

  plug :require_write when action in [:create, :import, :update, :create_draft]

  def index(conn, _params) do
    quizzes = Quizzes.list_created(conn.assigns.current_user)
    Response.ok(conn, Enum.map(quizzes, &Serializer.quiz/1))
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    with {:ok, version} <- Quizzes.create_draft_quiz(user, Params.quiz(params)),
         {:ok, full} <- Quizzes.get_owned_version_full(version.id, user) do
      Response.created(conn, Serializer.version(full))
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def import(conn, params) do
    case Quizzes.import_quiz(conn.assigns.current_user, Jason.encode!(params)) do
      {:ok, version} -> Response.created(conn, Serializer.version(version))
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    case Quizzes.get_owned_quiz(id, conn.assigns.current_user) do
      {:ok, quiz} -> Response.ok(conn, Serializer.quiz(quiz))
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def update(conn, %{"id" => id, "active" => active}) when is_boolean(active) do
    user = conn.assigns.current_user

    with {:ok, quiz} <- Quizzes.get_owned_quiz(id, user),
         {:ok, _updated} <- Quizzes.set_quiz_active(quiz, active, user),
         {:ok, reloaded} <- Quizzes.get_owned_quiz(id, user) do
      Response.ok(conn, Serializer.quiz(reloaded))
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def update(conn, %{"id" => _id}) do
    Response.validation(conn, ["active precisa ser true ou false"])
  end

  def create_draft(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, quiz} <- Quizzes.get_owned_quiz(id, user),
         {:ok, version} <- Quizzes.ensure_draft(quiz, user),
         {:ok, full} <- Quizzes.get_owned_version_full(version.id, user) do
      Response.created(conn, Serializer.version(full))
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  defp require_write(conn, _opts), do: ApiAuth.require_scope(conn, "quizzes:write")
end
