defmodule QuizProjectWeb.OgController do
  @moduledoc """
  Serve o card de preview (Open Graph) da tela de resultado como PNG. Público,
  sem login — é buscado pelos crawlers de preview. Em qualquer falha de geração
  devolve o fallback estático, para o crawler nunca receber erro.
  """
  use QuizProjectWeb, :controller

  alias QuizProjectWeb.OgImage

  def result(conn, %{"id" => id}) do
    png =
      case OgImage.result_png(id) do
        {:ok, png} -> png
        :error -> OgImage.fallback_png()
      end

    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, png)
  end
end
