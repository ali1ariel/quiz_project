defmodule QuizProjectWeb.Api.ProductController do
  use QuizProjectWeb, :controller

  alias QuizProject.Store
  alias QuizProjectWeb.Api.{Params, Response, Serializer}
  alias QuizProjectWeb.ApiAuth

  plug :require_write

  @doc """
  Cadastra um produto da Wish Store. Imagens não são aceitas por aqui —
  a galeria é sempre gerenciada pela interface (Configurações → Loja).
  """
  def create(conn, params) do
    user = conn.assigns.current_user

    case Store.create_product(user, Params.product(params)) do
      {:ok, product} -> Response.created(conn, Serializer.product(product))
      {:error, error} -> Response.render_error(conn, error)
    end
  end

  defp require_write(conn, _opts), do: ApiAuth.require_scope(conn, "store:write")
end
