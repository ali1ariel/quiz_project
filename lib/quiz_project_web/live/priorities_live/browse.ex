defmodule QuizProjectWeb.PrioritiesLive.Browse do
  @moduledoc """
  Listagem flat de todos os itens, com filtro por categoria (primária ou
  secundária), tag, tipo e arquivamento.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.PrioritiesLive.Components
  alias QuizProjectWeb.PrioritiesLive.ItemModal

  @item_types ~w(book quiz_goal course habit checklist manual)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(
       page_title: "Todos os itens",
       categories: Priorities.list_categories(user),
       tags: Priorities.list_tags(user),
       filters: %{category_id: nil, tag_id: nil, item_type: nil, archived: false},
       modal_item_id: nil
     )
     |> load_items()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      category_id: blank_to_nil(params["category_id"]),
      tag_id: blank_to_nil(params["tag_id"]),
      item_type: parse_item_type(params["item_type"]),
      archived: params["archived"] == "true"
    }

    {:noreply, socket |> assign(filters: filters) |> load_items()}
  end

  @impl true
  def handle_event("open_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, modal_item_id: id)}
  end

  @impl true
  def handle_event("close_item_modal", _params, socket) do
    {:noreply, socket |> assign(modal_item_id: nil) |> load_items()}
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
     |> load_items()}
  end

  defp load_items(socket) do
    user = socket.assigns.current_user
    f = socket.assigns.filters

    opts = [
      category_id: f.category_id,
      tag_id: f.tag_id,
      item_type: f.item_type,
      archived: f.archived
    ]

    assign(socket, items: Priorities.filter_items(user, opts))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_item_type(value) when value in @item_types, do: String.to_existing_atom(value)
  defp parse_item_type(_value), do: nil

  defp item_type_options do
    Enum.map(~w(book quiz_goal course habit checklist manual)a, fn type ->
      {Components.item_type_label(type), Atom.to_string(type)}
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :item_type_options, item_type_options())

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:priorities}
    >
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Todos os itens</h1>
          <p class="text-sm opacity-70">
            Todos os seus itens, de qualquer categoria, filtráveis por categoria, tag e tipo.
          </p>
        </div>

        <Components.sub_nav active={:browse} />

        <form
          id="browse-filters"
          phx-change="filter"
          class="grid grid-cols-2 gap-3 rounded-2xl border border-base-300 bg-base-100 p-4 sm:grid-cols-4"
        >
          <.input
            type="select"
            name="category_id"
            label="Categoria"
            value={@filters.category_id}
            options={Enum.map(@categories, &{&1.name, &1.id})}
            prompt="Todas"
          />
          <.input
            type="select"
            name="tag_id"
            label="Tag"
            value={@filters.tag_id}
            options={Enum.map(@tags, &{&1.name, &1.id})}
            prompt="Todas"
          />
          <.input
            type="select"
            name="item_type"
            label="Tipo"
            value={@filters.item_type && Atom.to_string(@filters.item_type)}
            options={@item_type_options}
            prompt="Todos"
          />
          <.input
            type="checkbox"
            name="archived"
            label="Incluir arquivados"
            checked={@filters.archived}
          />
        </form>

        <p :if={@items == []} class="text-sm opacity-60">Nenhum item encontrado com esses filtros.</p>

        <div :if={@items != []} class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <Components.item_card :for={item <- @items} item={item} show_category={true} />
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
