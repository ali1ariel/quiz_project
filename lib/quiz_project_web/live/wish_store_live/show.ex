defmodule QuizProjectWeb.WishStoreLive.Show do
  @moduledoc """
  Página de um produto: galeria de imagens, descrição completa e o botão de
  resgate, que debita a carteira (`QuizProject.Store.redeem_product/2`) e
  atualiza o saldo na hora — sem navegar para outro lugar, porque um mesmo
  produto pode ser resgatado mais de uma vez.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProject.Store
  alias QuizProjectWeb.WishStoreLive.Components

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Store.get_product(id, user) do
      {:ok, product} ->
        {:ok,
         assign(socket,
           page_title: product.name,
           product: product,
           balance: Priorities.wallet_balance(user),
           selected_image: 0
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Produto não encontrado.")
         |> push_navigate(to: ~p"/wish-store")}
    end
  end

  @impl true
  def handle_event("select_image", %{"index" => index}, socket) do
    {:noreply, assign(socket, selected_image: String.to_integer(index))}
  end

  @impl true
  def handle_event("redeem", _params, socket) do
    user = socket.assigns.current_user
    product = socket.assigns.product

    case Store.redeem_product(product, user) do
      {:ok, _redemption} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{product.name}\" resgatado!")
         |> assign(balance: Priorities.wallet_balance(user))}

      {:error, :insufficient_balance} ->
        {:noreply, put_flash(socket, :error, "Saldo insuficiente para este resgate.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível resgatar. Tente de novo.")}
    end
  end

  @impl true
  def render(assigns) do
    images = assigns.product.images || []
    main_image = Enum.at(images, assigns.selected_image) || List.first(images)
    affordable? = assigns.balance >= assigns.product.price

    assigns = assign(assigns, images: images, main_image: main_image, affordable?: affordable?)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:wish_store}
    >
      <div class="space-y-5">
        <.link
          navigate={~p"/wish-store"}
          class="flex w-fit items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3" /> Voltar à loja
        </.link>

        <div class="grid gap-8 md:grid-cols-2">
          <div class="space-y-3">
            <div class="qcard overflow-hidden rounded-2xl border border-base-300">
              <Components.product_image
                src={@main_image && image_url(@product.id, @main_image)}
                icon_class="size-16"
              />
            </div>

            <div :if={length(@images) > 1} class="flex flex-wrap gap-2">
              <button
                :for={{image, index} <- Enum.with_index(@images)}
                type="button"
                phx-click="select_image"
                phx-value-index={index}
                class={[
                  "size-16 shrink-0 overflow-hidden rounded-lg border-2 transition",
                  index == @selected_image && "border-primary",
                  index != @selected_image && "border-transparent opacity-70 hover:opacity-100"
                ]}
              >
                <img src={image_url(@product.id, image)} class="h-full w-full object-cover" alt="" />
              </button>
            </div>
          </div>

          <div class="flex flex-col gap-4">
            <h1 class="text-2xl font-bold tracking-tight">{@product.name}</h1>
            <p class="max-w-prose whitespace-pre-line text-[15px] leading-relaxed opacity-80">
              {@product.description}
            </p>

            <a
              :if={@product.link_url}
              href={@product.link_url}
              target="_blank"
              rel="noopener noreferrer"
              class="flex w-fit items-center gap-1 text-sm font-semibold text-primary hover:underline"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              {@product.link_text || @product.link_url}
            </a>

            <div class="h-px bg-base-300" />

            <Components.price_tag price={@product.price} size="text-3xl" />

            <button
              type="button"
              phx-click="redeem"
              disabled={!@affordable?}
              class="btn btn-primary w-fit gap-2 rounded-full px-6"
            >
              <.icon name="hero-check" class="size-4" /> Resgatar por {@product.price} pontos
            </button>

            <p class="text-xs opacity-60">
              <span :if={@affordable?}>
                Seu saldo atual é <strong class="opacity-100">{@balance}</strong>
                — depois do resgate ficam
                <strong class="opacity-100">{@balance - @product.price}</strong>
                pontos.
              </span>
              <span :if={!@affordable?} class="font-semibold text-error">
                Faltam {@product.price - @balance} pontos para este resgate.
              </span>
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp image_url(product_id, image), do: ~p"/wish-store/products/#{product_id}/images/#{image.id}"
end
