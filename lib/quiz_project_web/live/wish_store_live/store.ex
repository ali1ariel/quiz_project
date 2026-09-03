defmodule QuizProjectWeb.WishStoreLive.Store do
  @moduledoc """
  Vitrine da Wish Store: produtos cadastrados pelo usuário, mais recentes
  primeiro, com o saldo de pontos sempre visível — mesma intenção da
  carteira (`WishStoreLive.Wallet`), só que virada para "o que dá para
  resgatar" em vez de "o extrato de como cheguei até aqui".
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProject.Store
  alias QuizProjectWeb.WishStoreLive.Components

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       page_title: "Wish Store",
       balance: Priorities.wallet_balance(user),
       products: Store.list_products(user)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:wish_store}
    >
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Wish Store</h1>
          <p class="text-sm opacity-70">
            Troque os pontos ganhos concluindo atividades e prioridades por recompensas do catálogo.
          </p>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4">
          <Components.sub_nav active={:store} />
          <Components.balance_pill balance={@balance} />
        </div>

        <p
          :if={@products == []}
          class="rounded-3xl border border-dashed border-base-300 p-10 text-center text-sm opacity-50"
        >
          Nenhum produto cadastrado ainda.
        </p>

        <div :if={@products != []} class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <Components.product_card :for={product <- @products} product={product} balance={@balance} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
