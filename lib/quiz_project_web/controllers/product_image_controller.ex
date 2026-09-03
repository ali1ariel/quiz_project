defmodule QuizProjectWeb.ProductImageController do
  @moduledoc """
  Serve as imagens dos produtos da Wish Store.

  Mesmo racional do `BookImageController`: `send_file/3` entrega o arquivo
  ao kernel, sem passar pela VM nem ocupar conexão do banco. `product_id` é
  resolvido por `Store.get_product/2`, que já checa posse — sem isso um
  usuário poderia enumerar imagens de produto alheio pelo id.
  """
  use QuizProjectWeb, :controller

  alias QuizProject.Store
  alias QuizProject.Store.ImageStore

  def show(conn, %{"product_id" => product_id, "id" => image_id}) do
    with {:ok, product} <- Store.get_product(product_id, conn.assigns.current_user),
         %{path: path} <- Enum.find(product.images, &(&1.id == image_id)),
         {:ok, file, content_type} <- ImageStore.fetch(path) do
      conn
      |> put_resp_content_type(content_type)
      # A imagem só muda se a galeria do produto mudar, e o produto é de um
      # usuário só — cache privado e de longa duração é seguro.
      |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
      |> send_file(200, file)
    else
      _ -> send_resp(conn, 404, "")
    end
  end
end
