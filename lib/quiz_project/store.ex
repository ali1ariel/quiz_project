defmodule QuizProject.Store do
  @moduledoc """
  Catálogo de recompensas da Wish Store: produtos cadastrados pelo próprio
  usuário e resgatados com pontos da carteira de `QuizProject.Priorities`.
  Não existe catálogo global nem conceito de administrador — cada produto
  pertence a um usuário, e quem cadastra é quem resgata.

  Autorização de dono é verificada explicitamente aqui (o `actor` é o
  usuário logado); as ações Ash internas rodam com `authorize?: false`.
  """
  use Ash.Domain
  require Ash.Query

  alias QuizProject.Priorities
  alias QuizProject.Repo
  alias QuizProject.Store.ImageStore
  alias QuizProject.Store.Product
  alias QuizProject.Store.ProductImage
  alias QuizProject.Store.Redemption

  resources do
    resource Product
    resource ProductImage
    resource Redemption
  end

  @doc "`:ok` se `actor` é o dono do produto; `{:error, :unauthorized}` senão."
  def authorize_owner(%{user_id: user_id}, actor) do
    if actor && actor.id == user_id, do: :ok, else: {:error, :unauthorized}
  end

  # Produtos

  @doc "Produtos do usuário, mais recentes primeiro, com as imagens carregadas."
  def list_products(%{id: user_id}) do
    Product
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:images])
    |> Ash.read!(authorize?: false)
  end

  @doc "Um produto do usuário pelo id, com as imagens carregadas."
  def get_product(id, %{id: user_id}) do
    case Ash.get(Product, id, authorize?: false, load: [:images]) do
      {:ok, %Product{user_id: ^user_id} = product} -> {:ok, product}
      {:ok, _other} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Cadastra um produto novo para o usuário."
  def create_product(%{id: user_id}, attrs) do
    Product
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :user_id, user_id), authorize?: false)
    |> Ash.create()
  end

  @doc "Atualiza nome, descrição ou preço de um produto — recusa dono errado."
  def update_product(%Product{} = product, actor, attrs) do
    with :ok <- authorize_owner(product, actor) do
      product
      |> Ash.Changeset.for_update(:update, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  @doc """
  Adiciona uma imagem ao produto, na próxima posição da galeria — consulta a
  posição direto no banco, então funciona mesmo sem `product.images`
  carregado (o chamador não precisa ter dado `load: [:images]`).
  """
  def add_product_image(%Product{} = product, actor, path) do
    with :ok <- authorize_owner(product, actor) do
      position =
        ProductImage
        |> Ash.Query.filter(product_id == ^product.id)
        |> Ash.Query.sort(position: :desc)
        |> Ash.Query.limit(1)
        |> Ash.Query.select([:position])
        |> Ash.read!(authorize?: false)
        |> case do
          [%{position: position}] -> position + 1
          [] -> 0
        end

      ProductImage
      |> Ash.Changeset.for_create(
        :create,
        %{product_id: product.id, path: path, position: position},
        authorize?: false
      )
      |> Ash.create()
    end
  end

  @doc "Remove uma imagem do produto — apaga o registro e o arquivo em disco."
  def delete_product_image(%ProductImage{} = image, %Product{} = product, actor) do
    with :ok <- authorize_owner(product, actor),
         :ok <- Ash.destroy(image, authorize?: false) do
      ImageStore.delete(image.path)
      :ok
    end
  end

  # Resgate

  @doc """
  Resgata um produto: debita os pontos da carteira e registra o resgate.
  `{:error, :insufficient_balance}` se o saldo não cobrir o preço — checado
  de novo dentro da transação (`Priorities.spend_points/4`), então duas
  tentativas simultâneas não conseguem gastar o mesmo saldo duas vezes.
  """
  def redeem_product(%Product{} = product, user) do
    transaction_result =
      Repo.transaction(fn ->
        with {:ok, redemption, redemption_notifications} <-
               Redemption
               |> Ash.Changeset.for_create(
                 :create,
                 %{user_id: user.id, product_id: product.id, price: product.price},
                 authorize?: false
               )
               |> Ash.create(return_notifications?: true),
             {:ok, _entry, entry_notifications} <-
               Priorities.spend_points(
                 user,
                 product.price,
                 redemption.id,
                 "Resgate: \"#{product.name}\""
               ) do
          {redemption, redemption_notifications ++ entry_notifications}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    # Despachado só depois do commit — as duas criações acima rodam dentro do
    # `Repo.transaction` manual daqui, então o próprio Ash não consegue
    # despachar a notificação de cada uma sozinho (ver `Priorities.spend_points/4`).
    with {:ok, {redemption, notifications}} <- transaction_result do
      Ash.Notifier.notify(notifications)
      {:ok, redemption}
    end
  end
end
