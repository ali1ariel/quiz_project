defmodule QuizProjectWeb.BookImageController do
  @moduledoc """
  Serve as imagens extraídas do EPUB.

  `send_file/3` entrega o arquivo ao kernel: os bytes não passam pela VM nem
  ocupam conexão do banco, que existe para consulta transacional e não para
  transporte de estático.

  O caminho da URL é entrada não confiável e nunca é concatenado direto — quem
  resolve é o `ImageStore`, que recusa qualquer coisa que saia da pasta do
  material.
  """
  use QuizProjectWeb, :controller

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.ImageStore

  def show(conn, %{"id" => id, "path" => segments}) do
    path = Enum.join(segments, "/")

    with {:ok, material} <- AdaptiveStudy.get_material(id, conn.assigns.current_user),
         {:ok, file, content_type} <- ImageStore.fetch(material.id, path) do
      conn
      |> put_resp_content_type(content_type)
      # A imagem só muda se o livro for reingerido, e reingerir troca o material
      # inteiro. Privada porque o livro é de um usuário só.
      |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
      |> send_file(200, file)
    else
      _ -> send_resp(conn, 404, "")
    end
  end
end
