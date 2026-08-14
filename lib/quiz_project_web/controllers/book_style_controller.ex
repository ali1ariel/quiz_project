defmodule QuizProjectWeb.BookStyleController do
  @moduledoc """
  Serve a folha de estilo da editora, já filtrada e escopada sob `.qreader-book`.

  Rota própria em vez de `<style>` embutido na página porque a folha carrega as
  fontes do livro em base64: dentro do HTML ela iria junto a cada navegação
  entre capítulos, enquanto aqui o navegador busca uma vez e reusa.
  """
  use QuizProjectWeb, :controller

  alias QuizProject.AdaptiveStudy

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case AdaptiveStudy.get_material(id, user) do
      {:ok, %{reader_css: css}} when is_binary(css) ->
        conn
        |> put_resp_content_type("text/css")
        # A folha só muda quando o livro é reingerido, e reingerir troca o
        # material inteiro. Privado porque o material é de um usuário só.
        |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
        |> send_resp(200, css)

      {:ok, _material} ->
        conn
        |> put_resp_content_type("text/css")
        |> send_resp(200, "")

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
