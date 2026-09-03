defmodule QuizProjectWeb.WishStoreLive.Components do
  @moduledoc """
  Componentes compartilhados entre as telas da Wish Store: a sub-navegação
  (Carteira/Loja), o selo de pontos e o card de produto usado na listagem.
  """
  use QuizProjectWeb, :html

  @doc "Sub-navegação entre as telas da Wish Store."
  attr :active, :atom, required: true, doc: ":wallet ou :store"

  def sub_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-sm font-semibold">
      <.link
        navigate={~p"/wish-store"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :store)
        ]}
      >
        Loja
      </.link>
      <.link
        navigate={~p"/wish-store/wallet"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :wallet)
        ]}
      >
        Carteira
      </.link>
    </nav>
    """
  end

  defp tab_class(true), do: "bg-primary text-primary-content shadow-sm"
  defp tab_class(false), do: "bg-base-200 opacity-70 hover:opacity-100"

  @doc "Selo com o saldo atual de pontos."
  attr :balance, :integer, required: true

  def balance_pill(assigns) do
    ~H"""
    <div class="qcard flex items-center gap-2.5 rounded-full border border-base-300 px-4 py-2">
      <.points_badge />
      <span class="text-xs font-semibold opacity-60">Seu saldo</span>
      <span class="text-base font-bold tabular-nums">{@balance}</span>
    </div>
    """
  end

  @doc "Círculo com estrela — o ícone de pontos usado em toda a loja."
  attr :class, :string, default: "size-5"

  def points_badge(assigns) do
    ~H"""
    <span class={["grid shrink-0 place-items-center rounded-full bg-warning/15 text-warning", @class]}>
      <.icon name="hero-star-solid" class="size-3" />
    </span>
    """
  end

  @doc "Preço em pontos: selo + número. `size` é a classe de tamanho da fonte."
  attr :price, :integer, required: true
  attr :size, :string, default: "text-base"

  def price_tag(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5 font-bold tabular-nums", @size]}>
      <.points_badge /> {@price}
    </span>
    """
  end

  @doc """
  Card de produto da listagem: imagem de capa (ou um ícone de placeholder,
  sem produto ainda ter foto), nome, descrição, preço e se o saldo do
  usuário cobre o preço.
  """
  attr :product, :map, required: true, doc: "precisa de :id, :name, :description, :price, :images"
  attr :balance, :integer, required: true

  def product_card(assigns) do
    affordable? = assigns.balance >= assigns.product.price

    assigns =
      assign(assigns, cover_url: cover_image_url(assigns.product), affordable?: affordable?)

    ~H"""
    <.link
      navigate={~p"/wish-store/#{@product.id}"}
      class={[
        "qcard flex flex-col overflow-hidden rounded-2xl border",
        @affordable? && "border-base-300",
        !@affordable? && "border-dashed border-base-300 opacity-70"
      ]}
    >
      <.product_image src={@cover_url} />
      <div class="flex flex-1 flex-col gap-2 p-4">
        <h3 class="text-sm font-bold">{@product.name}</h3>
        <p class="line-clamp-2 text-xs opacity-65">{@product.description}</p>
        <div class="mt-auto flex items-center justify-between pt-2">
          <.price_tag price={@product.price} size="text-sm" />
          <span :if={@affordable?} class="text-xs font-bold text-primary">Ver detalhes →</span>
          <span :if={!@affordable?} class="text-xs font-bold text-error">
            Faltam {@product.price - @balance} pts
          </span>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Área quadrada (1:1) para a imagem de um produto: a foto inteira e
  centralizada, sem cortar nada — de fundo, a própria imagem ampliada e
  desfocada, preenchendo o quadrado atrás dela. Sem imagem, cai no ícone de
  placeholder.
  """
  attr :src, :string, default: nil
  attr :class, :string, default: "", doc: "classes extras no contêiner (raio, borda...)"
  attr :icon_class, :string, default: "size-10"

  def product_image(assigns) do
    ~H"""
    <div class={["relative aspect-square overflow-hidden bg-base-200", @class]}>
      <img
        :if={@src}
        src={@src}
        aria-hidden="true"
        alt=""
        class="absolute inset-0 h-full w-full scale-110 object-cover opacity-60 blur-lg"
      />
      <img :if={@src} src={@src} alt="" class="relative h-full w-full object-contain" />
      <div :if={!@src} class="grid h-full place-items-center text-base-content/30">
        <.icon name="hero-photo" class={@icon_class} />
      </div>
    </div>
    """
  end

  @doc """
  URL da imagem de capa (a de `position` mais baixa) de um produto, ou `nil`
  se ele ainda não tiver nenhuma — usado no card da listagem e na lista de
  produtos da tela de Configurações.
  """
  def cover_image_url(%{id: product_id, images: images}) do
    case List.first(images || []) do
      nil -> nil
      cover -> ~p"/wish-store/products/#{product_id}/images/#{cover.id}"
    end
  end
end
