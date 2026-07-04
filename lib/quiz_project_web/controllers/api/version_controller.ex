defmodule QuizProjectWeb.Api.VersionController do
  use QuizProjectWeb, :controller

  alias QuizProject.Quizzes
  alias QuizProjectWeb.Api.{Params, Response, Serializer}
  alias QuizProjectWeb.ApiAuth

  plug :require_write when action in [:update]
  plug :require_publish when action in [:publish]

  def show(conn, %{"id" => id}) do
    case Quizzes.get_owned_version_full(id, conn.assigns.current_user) do
      {:ok, version} -> Response.ok(conn, Serializer.version(version))
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, version} <- Quizzes.get_owned_version_full(id, user),
         {:ok, updated} <- Quizzes.update_draft(version, Params.quiz(params), user),
         {:ok, full} <- Quizzes.get_owned_version_full(updated.id, user) do
      Response.ok(conn, Serializer.version(full))
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def validate(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, version} <- Quizzes.get_owned_version_full(id, user) do
      case Quizzes.validate_draft(version, user) do
        :ok ->
          Response.ok(conn, %{valid: true, errors: []})

        {:error, errors} when is_list(errors) ->
          Response.ok(conn, %{valid: false, errors: errors})

        {:error, error} ->
          Response.render_error(conn, error)
      end
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  def publish(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, version} <- Quizzes.get_owned_version_full(id, user),
         {:ok, published} <- Quizzes.publish(version, user),
         {:ok, full} <- Quizzes.get_owned_version_full(published.id, user) do
      Response.ok(conn, Serializer.version(full))
    else
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  defp require_write(conn, _opts), do: ApiAuth.require_scope(conn, "quizzes:write")
  defp require_publish(conn, _opts), do: ApiAuth.require_scope(conn, "quizzes:publish")
end
