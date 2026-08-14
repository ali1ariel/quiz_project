defmodule QuizProjectWeb.Api.StudyController do
  use QuizProjectWeb, :controller

  alias QuizProject.AdaptiveStudy.ContentBundle
  alias QuizProjectWeb.Api.Response
  alias QuizProjectWeb.ApiAuth

  plug :require_write

  @doc """
  Recebe um bundle `.tar.gz` (campo `bundle` do multipart) gerado por
  `mix study.export` e substitui os materiais nele contidos, sempre
  associados ao dono do token — nunca a outro usuário.
  """
  def import(conn, %{"bundle" => %Plug.Upload{path: path}}) do
    {:ok, count} = ContentBundle.import(path, conn.assigns.current_user)
    Response.ok(conn, %{"materials_imported" => count})
  rescue
    e -> Response.validation(conn, ["Falha ao importar bundle: #{Exception.message(e)}"])
  end

  def import(conn, _params) do
    Response.validation(conn, ["campo \"bundle\" (arquivo) é obrigatório"])
  end

  defp require_write(conn, _opts), do: ApiAuth.require_scope(conn, "study:write")
end
