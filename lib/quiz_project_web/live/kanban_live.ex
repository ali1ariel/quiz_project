defmodule QuizProjectWeb.KanbanLive do
  @moduledoc """
  Tela do dia: seção própria do app (menu principal, `/today`), não uma aba
  de Prioridades. Raias por prioridade (uma por item com atividade hoje), com
  fluxo todo/fazendo/feito como filtro dentro da raia — não como colunas de
  fluxo globais. Capturas soltas (atividades sem item) ficam destacadas no
  topo, fora de qualquer raia, porque são o que ainda não tem pra onde ir.

  Mudar de fluxo é arrastar (mesmo padrão de `PrioritiesLive.Ranking`, drag
  nativo via `Components.draggable/1` + `Components.drop_zone/1`); "feito"
  não aceita drop — só os botões de resolução, que carregam uma intenção que
  um simples arrastar não capta.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.ActivityModal
  alias QuizProjectWeb.PrioritiesLive.Components

  @impl true
  def mount(_params, _session, socket) do
    # Geração preguiçosa das instâncias de hábito devidas hoje — só na
    # conexão via socket, não no render estático inicial (que roda duas
    # vezes por carregamento), mesmo cuidado que `UserAuth.on_mount(:notify_attempts)`
    # já toma pra evitar trabalho em dobro.
    if connected?(socket) do
      Priorities.ensure_today_habit_instances(socket.assigns.current_user)
    end

    {:ok, socket |> assign(page_title: "Hoje", modal_activity_id: nil) |> load_data()}
  end

  @impl true
  def handle_event("open_activity", %{"id" => id}, socket) do
    {:noreply, assign(socket, modal_activity_id: id)}
  end

  @impl true
  def handle_event("close_activity_modal", _params, socket) do
    {:noreply, socket |> assign(modal_activity_id: nil) |> load_data()}
  end

  @impl true
  def handle_event("create_capture", params, socket) do
    user = socket.assigns.current_user
    title = params |> Map.get("title", "") |> String.trim()
    category_id = params |> Map.get("category_id", "") |> blank_to_nil()

    if title == "" do
      {:noreply, put_flash(socket, :error, "Escreva alguma coisa antes de registrar.")}
    else
      attrs = capture_attrs(title, category_id, user)
      {:ok, _activity} = Priorities.create_activity(user, attrs)
      {:noreply, socket |> put_flash(:info, "Capturado.") |> load_data()}
    end
  end

  @impl true
  def handle_event("move_flow", %{"id" => id, "value" => value}, socket) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      case value do
        "fazendo" -> Priorities.start_activity(activity, user)
        "todo" -> Priorities.back_to_todo_activity(activity, user)
        _ -> :ok
      end
    end

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("complete_activity", %{"id" => id}, socket),
    do: {:noreply, resolve(socket, id, &Priorities.complete_activity/2)}

  @impl true
  def handle_event("mark_not_done", %{"id" => id}, socket),
    do: {:noreply, resolve(socket, id, &Priorities.mark_activity_not_done/2)}

  @impl true
  def handle_event("discard_activity", %{"id" => id}, socket),
    do: {:noreply, resolve(socket, id, &Priorities.discard_activity/2)}

  @impl true
  def handle_event("assign_item", %{"activity_id" => activity_id, "item_id" => item_id}, socket) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(activity_id, user),
         {:ok, item} <- Priorities.get_item(item_id, user) do
      Priorities.assign_activity_to_item(activity, item, user)
    end

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event(
        "assign_category",
        %{"activity_id" => activity_id, "category_id" => category_id},
        socket
      ) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(activity_id, user),
         {:ok, category} <- Priorities.get_category(category_id, user) do
      item = Priorities.general_item_for_category(category)
      Priorities.assign_activity_to_item(activity, item, user)
    end

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:kanban_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # `category_id` é opcional: sem ele a atividade nasce solta de verdade;
  # com ele, nasce presa ao item "Geral" da categoria — meio-termo entre
  # solta e presa a uma prioridade específica.
  defp capture_attrs(title, nil, _user), do: %{title: title}

  defp capture_attrs(title, category_id, user) do
    case Priorities.get_category(category_id, user) do
      {:ok, category} ->
        %{title: title, item_id: Priorities.general_item_for_category(category).id}

      _ ->
        %{title: title}
    end
  end

  defp resolve(socket, id, fun) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      fun.(activity, user)
    end

    load_data(socket)
  end

  defp load_data(socket) do
    user = socket.assigns.current_user

    assign(socket,
      lanes: Priorities.list_today_lanes(user),
      loose_captures: Priorities.list_loose_captures(user),
      categories: Priorities.list_categories(user)
    )
  end

  defp activities_in(lane, flow), do: Map.get(lane.activities, flow, [])

  defp lane_count(lane), do: lane.activities |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:kanban}
    >
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Hoje</h1>
          <p class="text-sm opacity-70">
            Poucas frentes, cada uma com o que está pendente, em andamento ou já feito hoje —
            em vez de uma lista só, misturada.
          </p>
        </div>

        <div id="loose-captures" class="space-y-3 rounded-3xl border border-base-300 bg-base-100 p-4">
          <div class="flex items-center justify-between gap-3">
            <h2 class="flex items-center gap-2 text-lg font-bold">
              <.icon name="hero-inbox" class="size-5 opacity-60" /> Capturas soltas
            </h2>
            <span
              :if={@loose_captures != []}
              class="rounded-full bg-error/10 px-2.5 py-0.5 text-xs font-bold text-error"
            >
              {length(@loose_captures)}
            </span>
          </div>

          <form id="capture-form" phx-submit="create_capture" class="flex flex-wrap items-end gap-3">
            <div class="min-w-48 flex-1">
              <.input type="text" name="title" value="" placeholder="Anotar algo rápido..." />
            </div>
            <div class="w-44">
              <.input
                type="select"
                name="category_id"
                label="Categoria (opcional)"
                value=""
                options={Enum.map(@categories, &{&1.name, &1.id})}
                prompt="Fica solta"
              />
            </div>
            <div class="fieldset mb-2">
              <label>
                <span class="label mb-1 invisible">Registrar</span>
                <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
                  Registrar
                </button>
              </label>
            </div>
          </form>

          <p :if={@loose_captures == []} class="text-sm opacity-50">
            Nada solto — tudo categorizado.
          </p>

          <div :for={activity <- @loose_captures} class="space-y-2">
            <Components.activity_card activity={activity} show_age?={true}>
              <:actions>
                <button
                  phx-click="complete_activity"
                  phx-value-id={activity.id}
                  class="btn btn-success btn-sm rounded-full"
                >
                  <.icon name="hero-check" class="size-4" /> Concluir
                </button>
                <button
                  :for={item <- Priorities.suggest_items_for_activity(activity)}
                  phx-click="assign_item"
                  phx-value-activity_id={activity.id}
                  phx-value-item_id={item.id}
                  class="btn btn-soft btn-sm rounded-full"
                  title={"Associar a \"#{item.title}\""}
                >
                  {item.title}
                </button>
                <button
                  :for={category <- @categories}
                  phx-click="assign_category"
                  phx-value-activity_id={activity.id}
                  phx-value-category_id={category.id}
                  class="btn btn-outline btn-sm rounded-full"
                  title={"Categorizar em \"#{category.name}\", sem virar prioridade"}
                >
                  {category.name}
                </button>
              </:actions>
            </Components.activity_card>
          </div>
        </div>

        <p
          :if={@lanes == []}
          class="rounded-3xl border border-dashed border-base-300 p-10 text-center text-sm opacity-50"
        >
          Nenhuma atividade presa a uma prioridade hoje.
        </p>

        <div :for={lane <- @lanes} class="space-y-3">
          <div class="flex items-center justify-between gap-3">
            <h2 class="flex items-center gap-2 text-lg font-bold">
              <span class={[
                "size-2.5 shrink-0 rounded-full",
                elem(Components.category_colors(lane.item.category_id), 1)
              ]}></span>
              <%= if lane.item.general do %>
                {lane.item.title}
              <% else %>
                <.link navigate={~p"/priorities/#{lane.item.id}"} class="hover:underline">
                  {lane.item.title}
                </.link>
              <% end %>
            </h2>
            <span class="text-xs font-semibold opacity-60">{lane_count(lane)} atividades</span>
          </div>

          <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
            <div class="space-y-2">
              <h3 class="text-xs font-bold uppercase tracking-wide opacity-50">A fazer</h3>
              <Components.drop_zone
                id={"lane-#{lane.item.id}-todo"}
                drag_group={"today-lane-#{lane.item.id}"}
                mode="move"
                event="move_flow"
                value="todo"
                class="min-h-16 space-y-2 rounded-2xl border border-dashed border-base-300 p-2"
              >
                <p :if={activities_in(lane, :todo) == []} class="py-4 text-center text-xs opacity-40">
                  Nada por aqui
                </p>
                <Components.draggable
                  :for={activity <- activities_in(lane, :todo)}
                  id={"activity-drag-#{activity.id}"}
                  drag_id={activity.id}
                >
                  <Components.activity_card activity={activity}>
                    <:actions>
                      <.resolve_buttons activity={activity} />
                    </:actions>
                  </Components.activity_card>
                </Components.draggable>
              </Components.drop_zone>
            </div>

            <div class="space-y-2">
              <h3 class="text-xs font-bold uppercase tracking-wide opacity-50">Fazendo</h3>
              <Components.drop_zone
                id={"lane-#{lane.item.id}-fazendo"}
                drag_group={"today-lane-#{lane.item.id}"}
                mode="move"
                event="move_flow"
                value="fazendo"
                class="min-h-16 space-y-2 rounded-2xl border border-dashed border-base-300 p-2"
              >
                <p
                  :if={activities_in(lane, :fazendo) == []}
                  class="py-4 text-center text-xs opacity-40"
                >
                  Nada em andamento
                </p>
                <Components.draggable
                  :for={activity <- activities_in(lane, :fazendo)}
                  id={"activity-drag-#{activity.id}"}
                  drag_id={activity.id}
                >
                  <Components.activity_card activity={activity}>
                    <:actions>
                      <.resolve_buttons activity={activity} />
                    </:actions>
                  </Components.activity_card>
                </Components.draggable>
              </Components.drop_zone>
            </div>

            <div class="space-y-2">
              <h3 class="text-xs font-bold uppercase tracking-wide opacity-50">Feito</h3>
              <div class="min-h-16 space-y-2 rounded-2xl border border-base-200 bg-base-200/40 p-2">
                <p
                  :if={activities_in(lane, :feito) == []}
                  class="py-4 text-center text-xs opacity-40"
                >
                  Nada concluído ainda
                </p>
                <Components.activity_card
                  :for={activity <- activities_in(lane, :feito)}
                  activity={activity}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <.live_component
        :if={@modal_activity_id}
        module={ActivityModal}
        id={"activity-modal-#{@modal_activity_id}"}
        activity_id={@modal_activity_id}
        current_user={@current_user}
      />
    </Layouts.app>
    """
  end

  attr :activity, :map, required: true

  defp resolve_buttons(assigns) do
    ~H"""
    <button
      phx-click="complete_activity"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title="Concluir"
    >
      <.icon name="hero-check" class="size-4 text-success" />
    </button>
    <button
      phx-click="mark_not_done"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title="Não cumprida"
    >
      <.icon name="hero-x-mark" class="size-4 text-warning" />
    </button>
    <button
      phx-click="discard_activity"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title="Descartar"
    >
      <.icon name="hero-trash" class="size-4 opacity-50" />
    </button>
    """
  end
end
