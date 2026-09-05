defmodule QuizProjectWeb.SettingsLive.ProductForm do
  @moduledoc """
  Cadastro e edição de um produto da Wish Store: nome, preço em pontos,
  descrição e uma ou mais imagens. Única tela de cadastro do app — a loja
  (`WishStoreLive.Store`) só lista e resgata, quem cria e edita é sempre
  daqui, a partir da lista de produtos em Configurações
  (`~p"/settings?tab=store&store_tab=products"`), pra onde volta ao salvar
  ou cancelar.

  `live_action` (`:new` | `:edit`, do roteador) decide se cria ou atualiza;
  o formulário é o mesmo dos dois lados — só o que já existe (produto,
  imagens) muda.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Store
  alias QuizProject.Store.ImageStore
  alias QuizProjectWeb.WishStoreLive.Components

  @max_images 6
  @max_file_size 5_000_000

  defp products_url, do: ~p"/settings?tab=store&store_tab=products"

  @impl true
  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :edit}} = socket) do
    case Store.get_product(id, socket.assigns.current_user) do
      {:ok, product} ->
        {:ok,
         socket
         |> assign(
           page_title: "Editar produto",
           product: product,
           existing_images: product.images || []
         )
         |> assign_form_fields()
         |> allow_images_upload()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Produto não encontrado.")
         |> push_navigate(to: products_url())}
    end
  end

  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    {:ok,
     socket
     |> assign(page_title: "Novo produto", product: nil, existing_images: [])
     |> assign_form_fields()
     |> allow_images_upload()}
  end

  defp assign_form_fields(socket) do
    product = socket.assigns.product

    assign(socket,
      name: (product && product.name) || "",
      description: (product && product.description) || "",
      price: (product && to_string(product.price)) || "",
      link_url: (product && product.link_url) || "",
      link_text: (product && product.link_text) || "",
      max_images: @max_images
    )
  end

  defp allow_images_upload(socket) do
    allow_upload(socket, :images,
      accept: ~w(.png .jpg .jpeg .webp),
      max_entries: @max_images,
      max_file_size: @max_file_size
    )
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    {:noreply,
     assign(socket,
       name: Map.get(params, "name", ""),
       description: Map.get(params, "description", ""),
       price: Map.get(params, "price", ""),
       link_url: Map.get(params, "link_url", ""),
       link_text: Map.get(params, "link_text", "")
     )}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("remove_existing_image", %{"id" => image_id}, socket) do
    user = socket.assigns.current_user
    product = socket.assigns.product
    image = Enum.find(socket.assigns.existing_images, &(&1.id == image_id))

    case image && Store.delete_product_image(image, product, user) do
      :ok ->
        {:noreply,
         update(socket, :existing_images, &Enum.reject(&1, fn i -> i.id == image_id end))}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a imagem.")}
    end
  end

  @impl true
  def handle_event("save", %{"product" => params}, socket) do
    user = socket.assigns.current_user

    with {:ok, price} <- parse_price(params["price"]),
         attrs = %{
           name: String.trim(params["name"] || ""),
           description: String.trim(params["description"] || ""),
           price: price,
           link_url: blank_to_nil(params["link_url"]),
           link_text: blank_to_nil(params["link_text"])
         },
         {:ok, product} <- save_product(socket, attrs) do
      consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
        extension = entry.client_name |> Path.extname() |> String.downcase()
        relative_path = ImageStore.put(product.id, extension, File.read!(path))
        Store.add_product_image(product, user, relative_path)
        {:ok, relative_path}
      end)

      {:noreply,
       socket
       |> put_flash(:info, save_flash_message(socket, product))
       |> push_navigate(to: products_url())}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível salvar. Confira os campos.")}
    end
  end

  defp save_product(%{assigns: %{live_action: :new, current_user: user}}, attrs) do
    Store.create_product(user, attrs)
  end

  defp save_product(
         %{assigns: %{live_action: :edit, product: product, current_user: user}},
         attrs
       ) do
    Store.update_product(product, user, attrs)
  end

  defp save_flash_message(%{assigns: %{live_action: :new}}, product),
    do: "\"#{product.name}\" cadastrado."

  defp save_flash_message(%{assigns: %{live_action: :edit}}, product),
    do: "\"#{product.name}\" atualizado."

  defp parse_price(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {price, ""} when price > 0 -> {:ok, price}
      _ -> :error
    end
  end

  defp parse_price(_value), do: :error

  defp blank_to_nil(value) do
    case value && String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @impl true
  def render(assigns) do
    total_images = length(assigns.existing_images) + length(assigns.uploads.images.entries)

    cover_url =
      Components.cover_image_url(%{
        id: assigns.product && assigns.product.id,
        images: assigns.existing_images
      })

    assigns = assign(assigns, total_images: total_images, cover_url: cover_url)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:account}
    >
      <div class="space-y-5">
        <.link
          navigate={~p"/settings?tab=store&store_tab=products"}
          class="flex w-fit items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3" /> Voltar aos produtos
        </.link>

        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">{@page_title}</h1>
          <p class="text-sm opacity-70">
            Nome, descrição, preço em pontos, link externo e imagens do produto.
          </p>
        </div>

        <form
          id="product-form"
          phx-change="validate"
          phx-submit="save"
          class="grid gap-8 md:grid-cols-[1fr_320px]"
        >
          <div class="space-y-5">
            <div class="space-y-2">
              <label class="block text-sm font-semibold opacity-75">Imagens</label>
              <p class="text-xs opacity-55">A primeira é a capa exibida na listagem.</p>

              <div class="flex flex-wrap gap-3" phx-drop-target={@uploads.images.ref}>
                <div
                  :for={image <- @existing_images}
                  class="relative size-24 overflow-hidden rounded-xl border border-base-300"
                >
                  <img
                    src={Components.cover_image_url(%{id: @product.id, images: [image]})}
                    class="h-full w-full object-cover"
                    alt=""
                  />
                  <button
                    type="button"
                    phx-click="remove_existing_image"
                    phx-value-id={image.id}
                    class="absolute right-1 top-1 grid size-5 place-items-center rounded-full bg-neutral/70 text-neutral-content"
                    aria-label="Remover imagem"
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </div>

                <div
                  :for={entry <- @uploads.images.entries}
                  class="relative size-24 overflow-hidden rounded-xl border border-base-300"
                >
                  <.live_img_preview entry={entry} class="h-full w-full object-cover" />
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="absolute right-1 top-1 grid size-5 place-items-center rounded-full bg-neutral/70 text-neutral-content"
                    aria-label="Remover imagem"
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                  <span
                    :if={entry.progress < 100}
                    class="absolute inset-x-0 bottom-0 h-1 bg-primary/20"
                  >
                    <span class="block h-full bg-primary" style={"width: #{entry.progress}%"} />
                  </span>
                </div>

                <label
                  :if={@total_images < @max_images}
                  class="flex size-24 shrink-0 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border-2 border-dashed border-base-300 text-center transition hover:border-primary"
                >
                  <.icon name="hero-plus" class="size-5 opacity-60" />
                  <span class="text-[11px] font-semibold opacity-60">Adicionar</span>
                  <.live_file_input upload={@uploads.images} class="hidden" />
                </label>
              </div>

              <p class="text-xs opacity-55">PNG, JPG ou WEBP, até 5 MB cada.</p>
              <p :for={err <- upload_errors(@uploads.images)} class="text-xs text-error">
                {upload_error(err)}
              </p>
            </div>

            <div class="flex gap-4">
              <div class="flex-1 space-y-2">
                <label for="product-name" class="block text-sm font-semibold opacity-75">
                  Nome do produto
                </label>
                <input
                  type="text"
                  id="product-name"
                  name="product[name]"
                  value={@name}
                  required
                  maxlength="120"
                  class="input input-bordered w-full rounded-xl"
                />
              </div>

              <div class="w-40 space-y-2">
                <label for="product-price" class="block text-sm font-semibold opacity-75">
                  Preço em pontos
                </label>
                <div class="relative">
                  <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2">
                    <Components.points_badge class="size-4" />
                  </span>
                  <input
                    type="number"
                    id="product-price"
                    name="product[price]"
                    value={@price}
                    min="1"
                    step="1"
                    required
                    class="input input-bordered w-full rounded-xl pl-9 font-bold"
                  />
                </div>
              </div>
            </div>

            <div class="space-y-2">
              <label for="product-description" class="block text-sm font-semibold opacity-75">
                Descrição
              </label>
              <textarea
                id="product-description"
                name="product[description]"
                rows="4"
                required
                maxlength="2000"
                class="textarea textarea-bordered w-full rounded-xl"
              >{@description}</textarea>
            </div>

            <div class="flex gap-4">
              <div class="flex-1 space-y-2">
                <label for="product-link-url" class="block text-sm font-semibold opacity-75">
                  Link do produto (opcional)
                </label>
                <input
                  type="url"
                  id="product-link-url"
                  name="product[link_url]"
                  value={@link_url}
                  maxlength="2048"
                  placeholder="https://..."
                  class="input input-bordered w-full rounded-xl"
                />
              </div>

              <div class="flex-1 space-y-2">
                <label for="product-link-text" class="block text-sm font-semibold opacity-75">
                  Texto do link
                </label>
                <input
                  type="text"
                  id="product-link-text"
                  name="product[link_text]"
                  value={@link_text}
                  maxlength="120"
                  placeholder="Ver na loja"
                  class="input input-bordered w-full rounded-xl"
                />
              </div>
            </div>

            <div class="flex gap-3 pt-2">
              <button type="submit" class="btn btn-primary rounded-full px-8">
                Salvar produto
              </button>
              <.link
                navigate={~p"/settings?tab=store&store_tab=products"}
                class="btn btn-ghost rounded-full px-6"
              >
                Cancelar
              </.link>
            </div>
          </div>

          <div class="space-y-2">
            <span class="text-xs font-bold uppercase tracking-wide opacity-50">Pré-visualização</span>

            <div class="qcard flex flex-col overflow-hidden rounded-2xl border border-base-300">
              <%!-- Sem capa ainda (ou capa nova, pendente): não repete
                   `<.live_img_preview>` do primeiro upload aqui — o LiveView usa
                   o `ref` do entry como id do elemento, e o mesmo entry já
                   aparece uma vez na galeria acima, então renderizar de novo
                   duplicaria o id na página. --%>
              <Components.product_image src={@cover_url} />
              <div class="flex flex-1 flex-col gap-2 p-4">
                <h3 class="text-sm font-bold">{presence(@name, "Nome do produto")}</h3>
                <p class="line-clamp-2 text-xs opacity-65">
                  {presence(@description, "A descrição aparece aqui.")}
                </p>
                <div class="mt-auto flex items-center justify-between pt-2">
                  <Components.price_tag price={preview_price(@price)} size="text-sm" />
                  <span class="text-xs font-bold text-primary">Ver detalhes →</span>
                </div>
              </div>
            </div>

            <p class="text-xs opacity-55">É assim que o card aparece na listagem da loja.</p>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end

  defp presence("", fallback), do: fallback
  defp presence(value, _fallback), do: value

  defp preview_price(value) do
    case Integer.parse(to_string(value)) do
      {price, ""} when price > 0 -> price
      _ -> 0
    end
  end

  defp upload_error(:too_large), do: "A imagem passa de 5 MB."
  defp upload_error(:not_accepted), do: "Só imagens PNG, JPG ou WEBP são aceitas."
  defp upload_error(:too_many_files), do: "No máximo #{@max_images} imagens."
  defp upload_error(_error), do: "Não foi possível enviar esta imagem."
end
