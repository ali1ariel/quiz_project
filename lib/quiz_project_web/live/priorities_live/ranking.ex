defmodule QuizProjectWeb.PrioritiesLive.Ranking do
  @moduledoc """
  Bloco de prioridades misturadas: itens de categorias diferentes, agrupados
  numa tier list fixa S/A/B/C/D — vários itens podem ocupar o mesmo tier.
  Mover um item de faixa é arrastar-e-soltar (ver `Components.drop_zone/1`
  com `mode="move"`); as cinco faixas compartilham o mesmo `drag_group`, e é
  isso que permite um item cruzar de uma pra outra.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.PrioritiesLive.Components
  alias QuizProjectWeb.PrioritiesLive.ItemModal

  @tiers ~w(S A B C D)
  @drag_group "ranking-tiers"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(page_title: "Prioridades misturadas", modal_item_id: nil) |> load_data()}
  end

  @impl true
  def handle_event("set_tier", %{"id" => id, "value" => value}, socket) do
    user = socket.assigns.current_user

    with {:ok, item} <- Priorities.get_item(id, user),
         {:ok, tier} <- parse_tier(value) do
      {:ok, _} = Priorities.set_tier(item, tier, user)
    end

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("open_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, modal_item_id: id)}
  end

  @impl true
  def handle_event("close_item_modal", _params, socket) do
    {:noreply, socket |> assign(modal_item_id: nil) |> load_data()}
  end

  @impl true
  def handle_info({:priorities_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  def handle_info({:priorities_item_deleted, _id}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Item excluído definitivamente.")
     |> assign(modal_item_id: nil)
     |> load_data()}
  end

  defp load_data(socket) do
    user = socket.assigns.current_user

    assign(socket,
      tiers: Priorities.list_tiered_items(user),
      untiered: Priorities.list_untiered_items(user)
    )
  end

  defp parse_tier(""), do: {:ok, nil}
  defp parse_tier(value) when value in @tiers, do: {:ok, String.to_existing_atom(value)}
  defp parse_tier(_value), do: :error

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :drag_group, @drag_group)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:priorities}>
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Prioridades misturadas</h1>
          <p class="text-sm opacity-70">
            Itens de qualquer categoria, ranqueados numa escala só. Arraste um card pelo
            <.icon name="hero-bars-2" class="inline size-3.5 opacity-60" />
            para outra faixa — vários itens podem dividir o mesmo tier.
          </p>
        </div>

        <Components.sub_nav active={:ranking} />

        <div :for={{tier, items} <- @tiers} class="space-y-3">
          <h2 class="flex items-center gap-2 text-lg font-bold">
            <span class="grid size-8 place-items-center rounded-full bg-primary/10 text-primary">
              {tier}
            </span>
            Tier {tier}
          </h2>

          <Components.drop_zone
            id={"tier-drop-zone-#{tier}"}
            drag_group={@drag_group}
            mode="move"
            event="set_tier"
            value={to_string(tier)}
            class="grid min-h-20 grid-cols-1 gap-3 rounded-2xl border border-dashed border-base-300 p-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <p :if={items == []} class="col-span-full py-3 text-center text-sm opacity-40">
              Solte um item aqui
            </p>
            <Components.draggable
              :for={item <- items}
              id={"ranked-item-#{item.id}"}
              drag_id={item.id}
              drag_group={@drag_group}
            >
              <Components.item_card item={item} show_category={true} />
            </Components.draggable>
          </Components.drop_zone>
        </div>

        <div class="space-y-3 border-t border-base-300 pt-6">
          <h2 class="text-lg font-bold opacity-70">Sem tier</h2>

          <Components.drop_zone
            id="untiered-drop-zone"
            drag_group={@drag_group}
            mode="move"
            event="set_tier"
            value=""
            class="grid min-h-20 grid-cols-1 gap-3 rounded-2xl border border-dashed border-base-300 p-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <p :if={@untiered == []} class="col-span-full py-3 text-center text-sm opacity-40">
              Nenhum item sem tier
            </p>
            <Components.draggable
              :for={item <- @untiered}
              id={"ranked-item-#{item.id}"}
              drag_id={item.id}
              drag_group={@drag_group}
            >
              <Components.item_card item={item} show_category={true} />
            </Components.draggable>
          </Components.drop_zone>
        </div>
      </div>

      <.live_component
        :if={@modal_item_id}
        module={ItemModal}
        id={"item-modal-#{@modal_item_id}"}
        item_id={@modal_item_id}
        current_user={@current_user}
        standalone={false}
      />
    </Layouts.app>
    """
  end
end
