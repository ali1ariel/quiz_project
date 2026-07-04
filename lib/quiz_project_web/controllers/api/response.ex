defmodule QuizProjectWeb.Api.Response do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def ok(conn, data), do: json(conn, %{data: data})

  def created(conn, data) do
    conn
    |> put_status(:created)
    |> json(%{data: data})
  end

  def no_content(conn), do: send_resp(conn, :no_content, "")

  def validation(conn, errors) when is_list(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_error", details: errors}})
  end

  def render_error(conn, :unauthorized), do: not_found(conn)
  def render_error(conn, :not_found), do: not_found(conn)
  def render_error(conn, :question_not_found), do: not_found(conn)
  def render_error(conn, :not_draft), do: conflict(conn, "version_not_editable")
  def render_error(conn, :no_version), do: conflict(conn, "published_version_required")

  def render_error(conn, %Ash.Error.Invalid{} = error) do
    details =
      error.errors
      |> Enum.map(fn
        %{message: message} when is_binary(message) -> message
        other -> Exception.message(other)
      end)
      |> Enum.uniq()

    validation(conn, details)
  end

  def render_error(conn, errors) when is_list(errors), do: validation(conn, errors)

  def render_error(conn, _error) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{code: "operation_failed", message: "Não foi possível concluir a operação"}
    })
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "Recurso não encontrado"}})
  end

  defp conflict(conn, code) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: code, message: "A operação não é permitida no estado atual"}})
  end
end
