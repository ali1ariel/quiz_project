defmodule QuizProjectWeb.Api.QuestionController do
  use QuizProjectWeb, :controller

  alias QuizProject.Quizzes
  alias QuizProjectWeb.Api.{Params, Response, Serializer}
  alias QuizProjectWeb.ApiAuth

  plug :require_write

  def create(conn, %{"id" => version_id} = params) do
    user = conn.assigns.current_user

    with {:ok, version} <- Quizzes.get_owned_version_full(version_id, user),
         {:ok, options} <- Params.options(params),
         {:ok, question} <-
           Quizzes.upsert_question(version, Params.question(params), options || [], user) do
      Response.created(conn, Serializer.question(question))
    else
      {:error, error} when is_binary(error) -> Response.validation(conn, [error])
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, question, version} <- Quizzes.get_owned_question(id, user),
         {:ok, requested_options} <- Params.options(params),
         options <- requested_options || Enum.map(question.options, &Serializer.option_attrs/1),
         attrs <- Map.put(Params.question(params), :id, question.id),
         {:ok, updated} <- Quizzes.upsert_question(version, attrs, options, user) do
      Response.ok(conn, Serializer.question(updated))
    else
      {:error, error} when is_binary(error) -> Response.validation(conn, [error])
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, question, _version} <- Quizzes.get_owned_question(id, user),
         :ok <- Quizzes.delete_question(question, user) do
      Response.no_content(conn)
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  defp require_write(conn, _opts), do: ApiAuth.require_scope(conn, "quizzes:write")
end
