defmodule QuizProjectWeb.KanbanLive do
  @moduledoc """
  Tela do dia: seção própria do app (menu principal, `/today`), não uma aba
  de Prioridades. Board único (3 colunas: a fazer/fazendo/feito) com todas
  as atividades presas a um item ou hábito hoje, misturadas — sem raia por
  prioridade. O que diferencia um card do outro é só visual: a cor lateral
  e a badge da categoria do item/hábito associado (ver
  `Components.activity_card/1`). Capturas soltas (sem item nem hábito)
  ficam destacadas à parte, no topo, porque são o que ainda não tem pra
  onde ir.

  Hábito é sempre extensão de uma prioridade (`Habit.item_id`, nunca solto)
  — nasce direto pelo form de captura (checkbox "É um hábito?"), anexado
  via o mesmo dropdown "Anexar" de uma captura comum (categoria vira o item
  "Geral" dela, prioridade anexa direto), sem página própria pra navegar
  (streak fica visível ao abrir a atividade, `ActivityModal`).

  Mudar de fluxo é arrastar (mesmo padrão de `PrioritiesLive.Ranking`, via
  `Components.draggable/1` + `Components.drop_zone/1`, SortableJS); "feito"
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
      Priorities.clear_expired_snoozes(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Hoje",
       modal_activity_id: nil,
       snooze_activity: nil,
       capture_is_habit?: false,
       capture_frequency: "daily",
       capture_category_id: nil,
       attach_category_by_activity: %{}
     )
     |> load_data()}
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
  def handle_event("capture_form_change", params, socket) do
    category_id = params |> Map.get("category_id", "") |> blank_to_nil()

    {:noreply,
     assign(socket,
       capture_is_habit?: Map.get(params, "is_habit") == "true",
       capture_frequency: Map.get(params, "frequency", "daily"),
       capture_category_id: category_id
     )}
  end

  @impl true
  def handle_event("create_capture", params, socket) do
    user = socket.assigns.current_user
    title = params |> Map.get("title", "") |> String.trim()
    item_id = params |> Map.get("item_id", "") |> blank_to_nil()
    is_habit? = Map.get(params, "is_habit") == "true"

    cond do
      title == "" ->
        {:noreply, put_flash(socket, :error, "Escreva alguma coisa antes de registrar.")}

      is_habit? and is_nil(item_id) ->
        {:noreply,
         put_flash(socket, :error, "Escolha uma categoria e uma prioridade pra anexar o hábito.")}

      is_habit? ->
        create_habit_capture(socket, user, title, item_id, params)

      true ->
        create_loose_capture(socket, user, title, item_id)
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
  def handle_event("reopen_activity", %{"id" => id}, socket),
    do: {:noreply, resolve(socket, id, &Priorities.reopen_activity/2)}

  @impl true
  def handle_event("open_snooze", %{"id" => id}, socket) do
    activity =
      Enum.find(
        socket.assigns.todo_activities ++ socket.assigns.fazendo_activities,
        &(&1.id == id)
      )

    {:noreply, assign(socket, snooze_activity: activity)}
  end

  @impl true
  def handle_event("close_snooze_modal", _params, socket) do
    {:noreply, assign(socket, snooze_activity: nil)}
  end

  @impl true
  def handle_event("confirm_snooze", %{"until" => until}, socket) do
    user = socket.assigns.current_user
    activity = socket.assigns.snooze_activity

    case until != "" && Date.from_iso8601(until) do
      {:ok, date} ->
        case Priorities.snooze_activity(activity, date, user) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Adiada até #{Calendar.strftime(date, "%d/%m/%Y")}.")
             |> assign(snooze_activity: nil)
             |> load_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "A data precisa ser depois de hoje.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Escolha uma data.")}
    end
  end

  @impl true
  def handle_event(
        "attach_category_change",
        %{"activity_id" => activity_id, "category_id" => category_id},
        socket
      ) do
    category_id = blank_to_nil(category_id)

    {:noreply,
     update(
       socket,
       :attach_category_by_activity,
       &Map.put(&1, activity_id, category_id)
     )}
  end

  @impl true
  def handle_event(
        "attach_capture",
        %{"activity_id" => activity_id, "item_id" => item_id},
        socket
      ) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(activity_id, user),
         {:ok, %Priorities.Item{} = item} <- Priorities.resolve_attach_item(item_id, user) do
      Priorities.assign_activity_to_item(activity, item, user)
    end

    {:noreply,
     socket
     |> update(:attach_category_by_activity, &Map.delete(&1, activity_id))
     |> load_data()}
  end

  @impl true
  def handle_info({:kanban_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp create_habit_capture(socket, user, title, item_id, params) do
    with {:ok, %Priorities.Item{} = item} <- Priorities.resolve_attach_item(item_id, user) do
      attrs = Map.merge(%{title: title, item_id: item.id}, build_habit_attrs(params))

      case Priorities.create_habit(user, attrs) do
        {:ok, habit} ->
          Priorities.ensure_today_habit_instance(habit, user)

          {:noreply,
           socket
           |> put_flash(:info, "Hábito criado.")
           |> assign(
             capture_is_habit?: false,
             capture_frequency: "daily",
             capture_category_id: nil
           )
           |> load_data()}

        _ ->
          {:noreply, put_flash(socket, :error, "Não foi possível criar o hábito.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível criar o hábito.")}
    end
  end

  defp create_loose_capture(socket, user, title, item_id) do
    case Priorities.resolve_attach_item(item_id, user) do
      {:ok, item} ->
        attrs = if item, do: %{title: title, item_id: item.id}, else: %{title: title}
        {:ok, _activity} = Priorities.create_activity(user, attrs)

        {:noreply,
         socket
         |> put_flash(:info, "Capturado.")
         |> assign(capture_category_id: nil)
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível registrar.")}
    end
  end

  defp build_habit_attrs(%{"frequency" => "weekly"} = params) do
    %{frequency: :weekly, weekdays: parse_int_list(params["weekdays"]), month_days: []}
  end

  defp build_habit_attrs(%{"frequency" => "monthly"} = params) do
    %{frequency: :monthly, weekdays: [], month_days: parse_int_list(params["month_days"])}
  end

  defp build_habit_attrs(_params) do
    %{frequency: :daily, weekdays: [], month_days: []}
  end

  defp parse_int_list(nil), do: []
  defp parse_int_list(values) when is_list(values), do: Enum.map(values, &String.to_integer/1)

  defp resolve(socket, id, fun) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      fun.(activity, user)
    end

    load_data(socket)
  end

  defp load_data(socket) do
    user = socket.assigns.current_user
    by_flow = Priorities.list_today_activities_by_flow(user)

    assign(socket,
      todo_activities: Map.get(by_flow, :todo, []),
      fazendo_activities: Map.get(by_flow, :fazendo, []),
      feito_activities: Map.get(by_flow, :feito, []),
      loose_captures: Priorities.list_loose_captures(user),
      categories: Priorities.list_categories(user),
      items_by_category:
        Enum.group_by(Priorities.list_items_including_general(user), & &1.category_id)
    )
  end

  defp category_by_id(categories, id), do: Enum.find(categories, &(&1.id == id))

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

        <Components.kanban_sub_nav active={:today} />

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

          <form
            id="capture-form"
            phx-submit="create_capture"
            phx-change="capture_form_change"
            class="space-y-3"
          >
            <div class="flex flex-wrap items-end gap-3">
              <div class="min-w-48 flex-1">
                <.input type="text" name="title" value="" placeholder="Anotar algo rápido..." />
              </div>
              <div class="w-40">
                <.input
                  type="select"
                  name="category_id"
                  label="Categoria"
                  value={@capture_category_id || ""}
                  options={Enum.map(@categories, &{&1.name, &1.id})}
                  prompt="Fica solta"
                />
              </div>
              <div class="w-48">
                <.input
                  type="select"
                  name="item_id"
                  label="Prioridade"
                  value=""
                  options={
                    if @capture_category_id,
                      do:
                        Components.attach_item_options(
                          Map.get(@items_by_category, @capture_category_id, []),
                          category_by_id(@categories, @capture_category_id)
                        ),
                      else: []
                  }
                  prompt={if @capture_category_id, do: "Escolha", else: "Escolha a categoria"}
                  disabled={is_nil(@capture_category_id)}
                />
              </div>
              <div class="fieldset mb-2">
                <label class="label flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    name="is_habit"
                    value="true"
                    checked={@capture_is_habit?}
                    class="checkbox checkbox-sm"
                  /> É um hábito?
                </label>
              </div>
              <div class="fieldset mb-2">
                <label>
                  <span class="label mb-1 invisible">Registrar</span>
                  <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
                    {if @capture_is_habit?, do: "Criar hábito", else: "Registrar"}
                  </button>
                </label>
              </div>
            </div>

            <div :if={@capture_is_habit?} class="space-y-3 rounded-2xl border border-base-300 p-3">
              <.input
                type="select"
                name="frequency"
                label="Frequência"
                value={@capture_frequency}
                options={[
                  {"Diário", "daily"},
                  {"Dias da semana", "weekly"},
                  {"Dias do mês", "monthly"}
                ]}
              />

              <div :if={@capture_frequency == "weekly"} class="fieldset mb-2">
                <span class="label mb-1">Quais dias</span>
                <Components.day_toggle_group
                  name="weekdays[]"
                  selected={[]}
                  options={[
                    {"Segunda", "1"},
                    {"Terça", "2"},
                    {"Quarta", "3"},
                    {"Quinta", "4"},
                    {"Sexta", "5"},
                    {"Sábado", "6"},
                    {"Domingo", "7"}
                  ]}
                />
              </div>

              <div :if={@capture_frequency == "monthly"} class="fieldset mb-2">
                <span class="label mb-1">Quais dias do mês</span>
                <Components.day_toggle_group
                  name="month_days[]"
                  selected={[]}
                  options={Enum.map(1..31, &{to_string(&1), to_string(&1)})}
                  class="grid grid-cols-6 gap-1.5 sm:grid-cols-7"
                />
              </div>
            </div>
          </form>

          <p :if={@loose_captures == []} class="text-sm opacity-50">
            Nada solto — tudo categorizado.
          </p>

          <div
            :for={activity <- @loose_captures}
            id={"loose-capture-#{activity.id}"}
            class="space-y-2"
          >
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
                  phx-click="discard_activity"
                  phx-value-id={activity.id}
                  class="btn btn-ghost btn-sm"
                  title="Descartar"
                >
                  <.icon name="hero-trash" class="size-4 opacity-50" />
                </button>
                <% attach_category_id = Map.get(@attach_category_by_activity, activity.id) %>
                <form
                  id={"attach-category-form-#{activity.id}"}
                  phx-change="attach_category_change"
                  class="inline-flex items-center gap-1.5"
                >
                  <input type="hidden" name="activity_id" value={activity.id} />
                  <.input
                    type="select"
                    name="category_id"
                    value={attach_category_id || ""}
                    options={Enum.map(@categories, &{&1.name, &1.id})}
                    prompt="Anexar a..."
                    class="select select-sm select-bordered rounded-full"
                  />
                </form>
                <form
                  :if={attach_category_id}
                  id={"attach-item-form-#{activity.id}"}
                  phx-change="attach_capture"
                  class="inline-flex items-center"
                >
                  <input type="hidden" name="activity_id" value={activity.id} />
                  <.input
                    type="select"
                    name="item_id"
                    value=""
                    options={
                      Components.attach_item_options(
                        Map.get(@items_by_category, attach_category_id, []),
                        category_by_id(@categories, attach_category_id)
                      )
                    }
                    prompt="Qual prioridade?"
                    class="select select-sm select-bordered rounded-full"
                  />
                </form>
              </:actions>
            </Components.activity_card>
          </div>
        </div>

        <p
          :if={@todo_activities == [] and @fazendo_activities == [] and @feito_activities == []}
          class="rounded-3xl border border-dashed border-base-300 p-10 text-center text-sm opacity-50"
        >
          Nenhuma atividade presa a uma prioridade hoje.
        </p>

        <div
          :if={@todo_activities != [] or @fazendo_activities != [] or @feito_activities != []}
          class="grid grid-cols-1 gap-3 md:grid-cols-3"
        >
          <div class="space-y-2">
            <h3 class="text-xs font-bold uppercase tracking-wide opacity-50">A fazer</h3>
            <Components.drop_zone
              id="today-todo"
              drag_group="today-flow"
              mode="move"
              event="move_flow"
              value="todo"
              class="min-h-16 space-y-2 rounded-2xl border border-dashed border-base-300 p-2"
            >
              <p :if={@todo_activities == []} class="py-4 text-center text-xs opacity-40">
                Nada por aqui
              </p>
              <Components.draggable
                :for={activity <- @todo_activities}
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
              id="today-fazendo"
              drag_group="today-flow"
              mode="move"
              event="move_flow"
              value="fazendo"
              class="min-h-16 space-y-2 rounded-2xl border border-dashed border-base-300 p-2"
            >
              <p :if={@fazendo_activities == []} class="py-4 text-center text-xs opacity-40">
                Nada em andamento
              </p>
              <Components.draggable
                :for={activity <- @fazendo_activities}
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
              <p :if={@feito_activities == []} class="py-4 text-center text-xs opacity-40">
                Nada concluído ainda
              </p>
              <Components.activity_card :for={activity <- @feito_activities} activity={activity}>
                <:actions>
                  <button
                    phx-click="reopen_activity"
                    phx-value-id={activity.id}
                    class="btn btn-ghost btn-xs"
                    title="Reabrir — volta pra a fazer"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4 opacity-50" /> Reabrir
                  </button>
                </:actions>
              </Components.activity_card>
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

      <.snooze_modal :if={@snooze_activity} activity={@snooze_activity} />
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
      :if={is_nil(@activity.habit_id)}
      phx-click="open_snooze"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title="Adiar — some daqui até a data escolhida"
    >
      <.icon name="hero-clock" class="size-4 opacity-60" />
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

  attr :activity, :map, required: true

  defp snooze_modal(assigns) do
    assigns = assign(assigns, :min_date, Date.add(Date.utc_today(), 1))

    ~H"""
    <div id="snooze-modal">
      <div class="modal modal-open" phx-window-keydown="close_snooze_modal" phx-key="Escape">
        <div class="modal-box max-w-sm rounded-3xl">
          <h2 class="text-lg font-bold tracking-tight">Adiar atividade</h2>
          <p class="mt-1 text-sm opacity-70">
            "{@activity.title}" some da Tela do dia até a data escolhida — reaparece sozinha
            nesse dia.
          </p>

          <form id="snooze-form" phx-submit="confirm_snooze" class="mt-4 space-y-4">
            <.input
              type="date"
              name="until"
              label="Adiar até"
              value=""
              min={Date.to_iso8601(@min_date)}
              required
            />

            <div class="flex justify-end gap-2">
              <button
                type="button"
                phx-click="close_snooze_modal"
                class="btn btn-ghost btn-sm rounded-full"
              >
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
                Adiar
              </button>
            </div>
          </form>
        </div>

        <button
          type="button"
          phx-click="close_snooze_modal"
          class="modal-backdrop"
          aria-label="Fechar"
        >
          Fechar
        </button>
      </div>
    </div>
    """
  end
end
