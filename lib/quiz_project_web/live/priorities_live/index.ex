defmodule QuizProjectWeb.PrioritiesLive.Index do
  @moduledoc """
  Visão por categoria: cada categoria é uma seção com seus itens ativos,
  formulário inline pra criar categoria/item, e reordenação por
  arrastar-e-soltar (pelo handle do card, ver `Components.draggable/1`).
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.AdaptiveStudy
  alias QuizProject.Priorities
  alias QuizProject.Quizzes
  alias QuizProjectWeb.PrioritiesLive.Components
  alias QuizProjectWeb.PrioritiesLive.ItemModal

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Prioridades",
       show_new_category?: false,
       item_form_category_id: nil,
       item_form_type: "manual",
       item_form_expanded?: false,
       modal_item_id: nil
     )
     |> load_data()}
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
  def handle_event("toggle_new_category", _params, socket) do
    {:noreply, update(socket, :show_new_category?, &(!&1))}
  end

  @impl true
  def handle_event("create_category", %{"name" => name}, socket) do
    user = socket.assigns.current_user
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Dê um nome para a categoria.")}
    else
      {:ok, _} = Priorities.create_category(user, %{name: name})

      {:noreply,
       socket
       |> put_flash(:info, "Categoria criada.")
       |> assign(show_new_category?: false)
       |> load_data()}
    end
  end

  @impl true
  def handle_event("toggle_item_form", %{"category_id" => id}, socket) do
    new_id = if socket.assigns.item_form_category_id == id, do: nil, else: id

    {:noreply,
     assign(socket,
       item_form_category_id: new_id,
       item_form_type: "manual",
       item_form_expanded?: false
     )}
  end

  @impl true
  def handle_event("toggle_item_form_expanded", _params, socket) do
    {:noreply, update(socket, :item_form_expanded?, &(!&1))}
  end

  @impl true
  def handle_event("item_form_change", %{"item_type" => type}, socket) do
    {:noreply, assign(socket, item_form_type: type)}
  end

  @impl true
  def handle_event("create_item", params, socket) do
    user = socket.assigns.current_user
    category = Enum.find(socket.assigns.categories, &(&1.id == params["category_id"]))

    with true <- not is_nil(category),
         {:ok, attrs} <- build_item_attrs(params, socket.assigns.point_defaults.item_points),
         {:ok, _item} <- Priorities.create_item(user, category, attrs) do
      {:noreply,
       socket
       |> put_flash(:info, "Item adicionado.")
       |> assign(item_form_category_id: nil, item_form_type: "manual", item_form_expanded?: false)
       |> load_data()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível criar o item. Confira os campos.")}
    end
  end

  @impl true
  def handle_event("reorder_items", %{"zone_id" => category_id, "ordered_ids" => ids}, socket) do
    reorder(
      Priorities.list_primary_items(category_id),
      ids,
      &Priorities.reposition_item/3,
      socket
    )

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("reorder_categories", %{"ordered_ids" => ids}, socket) do
    reorder(socket.assigns.categories, ids, &Priorities.reposition_category/3, socket)
    {:noreply, load_data(socket)}
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

  # Recebe a ordem final dos ids que o drag-and-drop já refletiu na tela, e só
  # grava a posição de cada um — o hook `.DropZone` (`Components.drop_zone/1`)
  # é quem decide, no navegador, qual é essa ordem.
  defp reorder(records, ids, reposition_fun, socket) do
    user = socket.assigns.current_user
    by_id = Map.new(records, &{&1.id, &1})

    ids
    |> Enum.with_index()
    |> Enum.each(fn {id, index} ->
      case Map.get(by_id, id) do
        nil -> :ok
        record -> reposition_fun.(record, index, user)
      end
    end)
  end

  defp load_data(socket) do
    user = socket.assigns.current_user
    categories = Priorities.list_categories(user)

    sections =
      Enum.map(categories, fn category ->
        {primary, secondary} =
          category.id
          |> Priorities.list_items_by_category()
          |> Enum.split_with(&(&1.category_id == category.id))

        %{category: category, primary_items: primary, secondary_items: secondary}
      end)

    assign(socket,
      categories: categories,
      sections: sections,
      books: AdaptiveStudy.list_books(user),
      quizzes: Quizzes.list_created(user),
      point_defaults: Priorities.get_point_defaults(user)
    )
  end

  defp build_item_attrs(params, default_points) do
    with {:ok, item_type} <- parse_item_type(params["item_type"]),
         {:ok, tier} <- parse_tier(params["tier"] || "") do
      base = %{
        item_type: item_type,
        title: String.trim(params["title"] || ""),
        notes: params["notes"] || "",
        store_points: parse_int(params["store_points"]) || default_points,
        tier: tier
      }

      attrs =
        case item_type do
          :book ->
            Map.put(base, :study_material_id, blank_to_nil(params["study_material_id"]))

          :quiz_goal ->
            Map.put(base, :quiz_id, blank_to_nil(params["quiz_id"]))

          :course ->
            Map.merge(base, %{
              course_total_steps: parse_int(params["course_total_steps"]),
              course_access_link: blank_to_nil(params["course_access_link"]),
              course_access_login: blank_to_nil(params["course_access_login"]),
              course_access_password: blank_to_nil(params["course_access_password"])
            })

          _ ->
            base
        end

      {:ok, attrs}
    end
  end

  @item_types ~w(book quiz_goal course checklist manual)

  defp parse_item_type(value) when value in @item_types,
    do: {:ok, String.to_existing_atom(value)}

  defp parse_item_type(_value), do: :error

  @tiers ~w(S A B C D)

  defp parse_tier(""), do: {:ok, nil}
  defp parse_tier(value) when value in @tiers, do: {:ok, String.to_existing_atom(value)}
  defp parse_tier(_value), do: :error

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp quiz_name(%{versions: [latest | _]}), do: latest.name || "Quiz sem nome"
  defp quiz_name(_quiz), do: "Quiz sem nome"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :item_type_options, Components.item_type_options())

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:priorities}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-3 border-b border-base-300 pb-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Prioridades</h1>
            <p class="text-sm opacity-70">
              Categorias e itens que você quer acompanhar ao longo do tempo.
            </p>
          </div>
          <button
            id="new-category-btn"
            phx-click="toggle_new_category"
            class="btn btn-primary rounded-full px-6 max-sm:w-full"
          >
            <.icon name="hero-plus" class="size-4" /> Nova categoria
          </button>
        </div>

        <Components.sub_nav active={:categories} />

        <form
          :if={@show_new_category?}
          id="new-category-form"
          phx-submit="create_category"
          class="flex flex-wrap items-end gap-3 rounded-2xl border border-base-300 bg-base-100 p-4"
        >
          <div class="min-w-48 flex-1">
            <.input
              type="text"
              name="name"
              label="Nome da categoria"
              value=""
              placeholder="Ex: Livros"
              required
            />
          </div>
          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1 invisible">Criar</span>
              <button type="submit" class="btn btn-primary rounded-full px-6">Criar</button>
            </label>
          </div>
        </form>

        <%= if @categories == [] do %>
          <div class="rounded-3xl border border-dashed border-base-300 p-10 text-center">
            <.icon name="hero-flag" class="mx-auto size-10 opacity-40" />
            <h2 class="mt-3 text-lg font-bold">Nenhuma categoria ainda</h2>
            <p class="mx-auto mt-1 max-w-md text-sm opacity-70">
              Crie uma categoria — "Livros", "Hábitos", "Cursos" — e comece a adicionar itens.
            </p>
          </div>
        <% else %>
          <Components.drop_zone
            id="categories-drop-zone"
            drag_group="categories-list"
            event="reorder_categories"
            handle={true}
            class="space-y-8"
          >
            <Components.draggable
              :for={section <- @sections}
              id={"category-#{section.category.id}"}
              drag_id={section.category.id}
              handle={true}
            >
              <div class="space-y-3">
                <div class="flex items-center justify-between gap-3">
                  <h2 class="flex items-center gap-2 text-lg font-bold">
                    <span class={[
                      "size-2.5 shrink-0 rounded-full",
                      elem(Components.category_colors(section.category.id), 1)
                    ]}></span>
                    {section.category.name}
                  </h2>
                  <button
                    phx-click="toggle_item_form"
                    phx-value-category_id={section.category.id}
                    class="btn btn-soft btn-sm rounded-full"
                  >
                    <.icon name="hero-plus" class="size-3.5" /> Novo item
                  </button>
                </div>

                <form
                  :if={@item_form_category_id == section.category.id}
                  id={"new-item-form-#{section.category.id}"}
                  phx-submit="create_item"
                  phx-change="item_form_change"
                  class="space-y-3 rounded-2xl border border-base-300 bg-base-100 p-4"
                >
                  <input type="hidden" name="category_id" value={section.category.id} />
                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <.input
                      type="select"
                      name="item_type"
                      label="Tipo"
                      value={@item_form_type}
                      options={@item_type_options}
                    />
                    <.input
                      type="text"
                      name="title"
                      label={
                        if @item_form_type == "book",
                          do: "Título (opcional — usa o do livro)",
                          else: "Título"
                      }
                      value=""
                      required={@item_form_type != "book"}
                    />
                  </div>

                  <.input
                    :if={@item_form_type == "book"}
                    type="select"
                    name="study_material_id"
                    label="Livro"
                    value=""
                    options={Enum.map(@books, &{&1.title, &1.id})}
                    prompt="Escolha um livro"
                  />

                  <.input
                    :if={@item_form_type == "quiz_goal"}
                    type="select"
                    name="quiz_id"
                    label="Quiz"
                    value=""
                    options={Enum.map(@quizzes, &{quiz_name(&1), &1.id})}
                    prompt="Escolha um quiz"
                  />

                  <.input
                    :if={@item_form_type == "course"}
                    type="number"
                    name="course_total_steps"
                    label="Total de etapas (opcional)"
                    min="1"
                    value=""
                  />

                  <div :if={@item_form_type == "course"} class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                    <.input type="text" name="course_access_link" label="Link de acesso" value="" />
                    <.input type="text" name="course_access_login" label="Login" value="" />
                    <.input type="text" name="course_access_password" label="Senha" value="" />
                  </div>

                  <button
                    type="button"
                    phx-click="toggle_item_form_expanded"
                    class="flex items-center gap-1 text-xs font-semibold opacity-60 hover:opacity-100"
                  >
                    <.icon
                      name="hero-chevron-right"
                      class={["size-3.5 transition-transform", @item_form_expanded? && "rotate-90"]}
                    /> Mais opções
                  </button>

                  <div
                    :if={@item_form_expanded?}
                    class="space-y-3 rounded-2xl border border-base-200 p-3"
                  >
                    <.input type="textarea" name="notes" label="Notas (opcional)" value="" rows="2" />
                    <div class="flex flex-wrap items-end gap-4">
                      <div class="w-28">
                        <.input
                          type="number"
                          name="store_points"
                          label="Pontos"
                          value={@point_defaults.item_points}
                          min="0"
                        />
                      </div>
                      <div class="fieldset mb-2">
                        <span class="label mb-1">Tier</span>
                        <div class="flex flex-wrap gap-3">
                          <label class="flex items-center gap-1 text-sm">
                            <input type="radio" name="tier" value="" class="radio radio-sm" checked />
                            Sem tier
                          </label>
                          <label
                            :for={t <- ~w(S A B C D)}
                            class="flex items-center gap-1 text-sm font-semibold"
                          >
                            <input type="radio" name="tier" value={t} class="radio radio-sm" /> {t}
                          </label>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="toggle_item_form"
                      phx-value-category_id={section.category.id}
                      class="btn btn-ghost btn-sm rounded-full"
                    >
                      Cancelar
                    </button>
                    <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
                      Adicionar
                    </button>
                  </div>
                </form>

                <p :if={section.primary_items == []} class="text-sm opacity-60">
                  Nenhum item ainda.
                </p>

                <Components.drop_zone
                  :if={section.primary_items != []}
                  id={"items-drop-zone-#{section.category.id}"}
                  drag_group={"category-items-#{section.category.id}"}
                  event="reorder_items"
                  value={section.category.id}
                  class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
                >
                  <Components.draggable
                    :for={item <- section.primary_items}
                    id={"item-row-#{item.id}"}
                    drag_id={item.id}
                  >
                    <Components.item_card item={item} />
                  </Components.draggable>
                </Components.drop_zone>

                <div
                  :if={section.secondary_items != []}
                  class="space-y-2 border-t border-base-200 pt-3"
                >
                  <p class="text-xs font-semibold opacity-50">Também aqui via categoria secundária</p>
                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <Components.item_card :for={item <- section.secondary_items} item={item} />
                  </div>
                </div>
              </div>
            </Components.draggable>
          </Components.drop_zone>
        <% end %>
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
