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
  `Components.draggable/1` + `Components.drop_zone/1`, SortableJS) nas 3
  colunas, inclusive "Feito" — arrastar pra lá equivale a "Concluir"
  (`move_to_feito/2`); os botões de resolução continuam existindo pra quem
  quer "Não cumprida"/"Descartar", intenções que um simples arrastar não
  capta. Arrastar pra fora de "Feito" reabre a atividade antes de aplicar o
  novo flow (`move_to_todo/2`, `move_to_fazendo/2`), já que as actions de
  destino exigem uma atividade ainda não resolvida.
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

    point_defaults = Priorities.get_point_defaults(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       page_title: "Hoje",
       modal_activity_id: nil,
       snooze_activity: nil,
       capture_expanded?: false,
       capture_title: "",
       capture_notes: "",
       capture_type: "tarefa",
       capture_frequency: "daily",
       capture_category_id: nil,
       capture_item_id: nil,
       capture_tasks: [],
       capture_task_draft: "",
       capture_task_points_draft: to_string(point_defaults.activity_task_points),
       attach_category_by_activity: %{},
       point_defaults: point_defaults
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

    capture_item_id =
      if category_id == socket.assigns.capture_category_id do
        params |> Map.get("item_id", "") |> blank_to_nil() || socket.assigns.capture_item_id
      else
        general_item_id(socket.assigns.items_by_category, category_id)
      end

    {:noreply,
     assign(socket,
       capture_title: Map.get(params, "title", ""),
       capture_notes: Map.get(params, "notes", ""),
       capture_type: Map.get(params, "type", "tarefa"),
       capture_frequency: Map.get(params, "frequency", "daily"),
       capture_category_id: category_id,
       capture_item_id: capture_item_id,
       capture_task_draft: Map.get(params, "task_draft", ""),
       capture_task_points_draft: Map.get(params, "task_points_draft", "0")
     )}
  end

  @impl true
  def handle_event("toggle_capture_expanded", _params, socket) do
    {:noreply, update(socket, :capture_expanded?, &(!&1))}
  end

  @impl true
  def handle_event("add_capture_task", _params, socket) do
    title = String.trim(socket.assigns.capture_task_draft || "")

    points =
      parse_int(socket.assigns.capture_task_points_draft) ||
        socket.assigns.point_defaults.activity_task_points

    if title == "" do
      {:noreply, socket}
    else
      task = %{title: title, store_points: points}

      {:noreply,
       socket
       |> update(:capture_tasks, &(&1 ++ [task]))
       |> assign(
         capture_task_draft: "",
         capture_task_points_draft: to_string(socket.assigns.point_defaults.activity_task_points)
       )}
    end
  end

  @impl true
  def handle_event("remove_capture_task", %{"index" => index}, socket) do
    index = String.to_integer(index)
    {:noreply, update(socket, :capture_tasks, &List.delete_at(&1, index))}
  end

  @impl true
  def handle_event("create_capture", params, socket) do
    user = socket.assigns.current_user
    title = params |> Map.get("title", "") |> String.trim()
    item_id = params |> Map.get("item_id", "") |> blank_to_nil()
    is_habit? = Map.get(params, "type") == "habito"
    is_event? = Map.get(params, "type") == "evento"

    cond do
      title == "" ->
        {:noreply, put_flash(socket, :error, "Escreva alguma coisa antes de registrar.")}

      is_habit? and is_nil(item_id) ->
        {:noreply,
         put_flash(socket, :error, "Escolha uma categoria e uma prioridade pra anexar o hábito.")}

      is_habit? ->
        create_habit_capture(socket, user, title, item_id, params)

      true ->
        extra_attrs =
          event_attrs(is_event?, params)
          |> Map.merge(max_deadline_attrs(params))
          |> Map.merge(notes_attrs(params))
          |> Map.merge(store_points_attrs(params, socket.assigns.point_defaults.activity_points))

        create_loose_capture(socket, user, title, item_id, extra_attrs)
    end
  end

  @impl true
  def handle_event("move_flow", %{"id" => id, "value" => value}, socket) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      case value do
        "fazendo" -> move_to_fazendo(activity, user)
        "todo" -> move_to_todo(activity, user)
        "feito" -> move_to_feito(activity, user)
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
        socket.assigns.todo_activities ++
          socket.assigns.fazendo_activities ++ socket.assigns.loose_captures,
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
    event? = activity.kind == :evento

    case until != "" && Date.from_iso8601(until) do
      {:ok, date} ->
        result =
          if event?,
            do: Priorities.reschedule_activity(activity, date, user),
            else: Priorities.snooze_activity(activity, date, user)

        case result do
          {:ok, _} ->
            message =
              if event?,
                do: "Reagendado para #{Calendar.strftime(date, "%d/%m/%Y")}.",
                else: "Adiada até #{Calendar.strftime(date, "%d/%m/%Y")}."

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> assign(snooze_activity: nil)
             |> load_data()}

          {:error, _} ->
            message =
              if event?,
                do: "Não foi possível reagendar.",
                else: "A data precisa ser depois de hoje."

            {:noreply, put_flash(socket, :error, message)}
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

  defp reset_capture_assigns(point_defaults) do
    [
      capture_expanded?: false,
      capture_title: "",
      capture_notes: "",
      capture_type: "tarefa",
      capture_frequency: "daily",
      capture_category_id: nil,
      capture_item_id: nil,
      capture_tasks: [],
      capture_task_draft: "",
      capture_task_points_draft: to_string(point_defaults.activity_task_points)
    ]
  end

  defp create_habit_capture(socket, user, title, item_id, params) do
    with {:ok, %Priorities.Item{} = item} <- Priorities.resolve_attach_item(item_id, user) do
      attrs =
        %{title: title, item_id: item.id}
        |> Map.merge(build_habit_attrs(params))
        |> Map.merge(store_points_attrs(params, socket.assigns.point_defaults.habit_points))

      case Priorities.create_habit(user, attrs) do
        {:ok, habit} ->
          Priorities.ensure_today_habit_instance(habit, user)

          {:noreply,
           socket
           |> put_flash(:info, "Hábito criado.")
           |> assign(reset_capture_assigns(socket.assigns.point_defaults))
           |> load_data()}

        _ ->
          {:noreply, put_flash(socket, :error, "Não foi possível criar o hábito.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível criar o hábito.")}
    end
  end

  defp create_loose_capture(socket, user, title, item_id, extra_attrs) do
    case Priorities.resolve_attach_item(item_id, user) do
      {:ok, item} ->
        base = if item, do: %{title: title, item_id: item.id}, else: %{title: title}
        attrs = Map.merge(base, extra_attrs)
        {:ok, activity} = Priorities.create_activity(user, attrs)

        Enum.each(socket.assigns.capture_tasks, fn task ->
          Priorities.create_activity_task(activity, task.title, user, task.store_points)
        end)

        flash =
          if Map.get(extra_attrs, :kind) == :evento, do: "Evento criado.", else: "Capturado."

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> assign(reset_capture_assigns(socket.assigns.point_defaults))
         |> load_data()}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível registrar.")}
    end
  end

  # `logical_date` inválida ou em branco cai no default de hoje que
  # `Priorities.create_activity/2` já aplica — só força a data quando o
  # usuário de fato escolheu uma.
  defp event_attrs(false, _params), do: %{}

  defp event_attrs(true, params) do
    case params |> Map.get("event_date", "") |> Date.from_iso8601() do
      {:ok, date} -> %{kind: :evento, logical_date: date}
      _ -> %{kind: :evento}
    end
  end

  defp max_deadline_attrs(params) do
    case params |> Map.get("max_deadline", "") |> Date.from_iso8601() do
      {:ok, date} -> %{max_deadline: date}
      _ -> %{}
    end
  end

  defp notes_attrs(params) do
    case params |> Map.get("notes", "") |> String.trim() do
      "" -> %{}
      notes -> %{notes: notes}
    end
  end

  defp store_points_attrs(params, default) do
    case params |> Map.get("store_points", "") |> Integer.parse() do
      {points, _rest} -> %{store_points: points}
      :error -> %{store_points: default}
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
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

  # Arrastar pra fora de Feito precisa reabrir antes — `back_to_todo`/`start`
  # só aceitam atividade já em `fazendo`/`pendente`, então uma atividade
  # resolvida (`flow == :feito`) sempre passa por `reopen` primeiro.
  defp move_to_todo(%{flow: :feito} = activity, user),
    do: Priorities.reopen_activity(activity, user)

  defp move_to_todo(activity, user), do: Priorities.back_to_todo_activity(activity, user)

  defp move_to_fazendo(%{flow: :feito} = activity, user) do
    with {:ok, reopened} <- Priorities.reopen_activity(activity, user) do
      Priorities.start_activity(reopened, user)
    end
  end

  defp move_to_fazendo(activity, user), do: Priorities.start_activity(activity, user)

  # `:complete` não tem validação de estado (aceita reaplicar de qualquer
  # flow) — sem essa guarda, só reordenar dentro de Feito (mesma zona,
  # SortableJS ainda dispara `move_flow`) reverteria silenciosamente uma
  # atividade "não cumprida"/"descartada" pra "concluída".
  defp move_to_feito(%{flow: :feito}, _user), do: :ok
  defp move_to_feito(activity, user), do: Priorities.complete_activity(activity, user)

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

  defp general_item_id(_items_by_category, nil), do: nil

  defp general_item_id(items_by_category, category_id) do
    items_by_category
    |> Map.get(category_id, [])
    |> Enum.find(& &1.general)
    |> case do
      nil -> nil
      item -> item.id
    end
  end

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

        <div class="space-y-3">
          <div class="card qcard space-y-4 p-5">
            <h2 class="flex items-center gap-2 text-base font-bold">
              <.icon name="hero-inbox" class="size-5 opacity-50" /> Criar atividade
            </h2>

            <form
              id="capture-form"
              phx-submit="create_capture"
              phx-change="capture_form_change"
              class="space-y-4"
            >
              <div class="flex items-center gap-2">
                <div class="relative min-w-48 flex-1">
                  <.icon
                    name="hero-inbox"
                    class="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-base-content/45"
                  />
                  <input
                    type="text"
                    name="title"
                    value={@capture_title}
                    placeholder="Anotar algo rápido..."
                    class="input w-full rounded-full py-[0.8rem] pl-11 pr-4 text-[0.975rem]"
                  />
                </div>
                <button
                  type="submit"
                  class="btn btn-primary rounded-full px-[1.4rem] py-[0.8rem] text-[0.9rem]"
                  phx-disable-with="Registrando..."
                >
                  {cond do
                    @capture_type == "habito" -> "Criar hábito"
                    @capture_type == "evento" -> "Criar evento"
                    true -> "Registrar"
                  end}
                </button>
                <button
                  type="button"
                  phx-click="toggle_capture_expanded"
                  class="btn btn-ghost rounded-full p-[0.8rem]"
                  aria-expanded={to_string(@capture_expanded?)}
                  title={if @capture_expanded?, do: "Menos opções", else: "Mais opções"}
                >
                  <.icon
                    name="hero-adjustments-horizontal"
                    class={["size-5 transition-transform", @capture_expanded? && "rotate-180"]}
                  />
                </button>
              </div>

              <div :if={@capture_expanded?} class="space-y-4 border-t border-base-300 pt-4">
                <div class="flex flex-wrap items-end gap-3">
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
                      value={@capture_item_id || ""}
                      options={
                        if @capture_category_id,
                          do:
                            Components.attach_item_options(
                              Map.get(@items_by_category, @capture_category_id, []),
                              category_by_id(@categories, @capture_category_id)
                            ),
                          else: []
                      }
                      prompt={if @capture_category_id, do: nil, else: "Escolha a categoria"}
                      disabled={is_nil(@capture_category_id)}
                    />
                  </div>
                  <div class="w-40">
                    <.input type="date" name="max_deadline" label="Prazo máximo" value="" />
                  </div>
                  <div class="w-28">
                    <.input
                      type="number"
                      name="store_points"
                      label="Pontos"
                      value={
                        if @capture_type == "habito",
                          do: @point_defaults.habit_points,
                          else: @point_defaults.activity_points
                      }
                      min="0"
                    />
                  </div>
                </div>

                <div class="border-t border-base-200"></div>

                <div class="fieldset mb-2">
                  <span class="label mb-1">Tipo</span>
                  <div class="flex flex-wrap gap-2">
                    <label
                      :for={
                        {label_text, value, icon} <- [
                          {"Atividade", "tarefa", "hero-check-circle"},
                          {"Hábito", "habito", "hero-arrow-path"},
                          {"Evento", "evento", "hero-calendar-days"}
                        ]
                      }
                      class="flex cursor-pointer select-none items-center gap-1.5 rounded-full border border-base-300 bg-base-100 px-4 py-1.5 text-sm font-semibold opacity-70 transition hover:opacity-100 has-checked:border-primary has-checked:bg-primary has-checked:text-primary-content has-checked:opacity-100"
                    >
                      <input
                        type="radio"
                        name="type"
                        value={value}
                        checked={@capture_type == value}
                        class="hidden"
                      />
                      <.icon name={icon} class="size-4" /> {label_text}
                    </label>
                  </div>
                </div>

                <div
                  :if={@capture_type == "evento"}
                  class="flex flex-wrap items-center gap-2 rounded-xl bg-primary/5 p-3 text-sm"
                >
                  <span class="font-semibold">Data do evento:</span>
                  <input
                    type="date"
                    name="event_date"
                    value={Date.to_iso8601(Date.utc_today())}
                    class="input input-sm w-40 rounded-lg text-center"
                  />
                  <span class="text-xs opacity-60">
                    — vira evento sincronizado com o Google Agenda, se conectado (ver Configurações).
                  </span>
                </div>

                <div
                  :if={@capture_type == "habito"}
                  class="space-y-3 rounded-xl bg-primary/5 p-3"
                >
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

                <div class="border-t border-base-200"></div>

                <.input
                  type="textarea"
                  name="notes"
                  label="Descrição (opcional)"
                  value={@capture_notes}
                  rows="2"
                  placeholder="Mais contexto sobre essa atividade..."
                />

                <div class="space-y-2 rounded-xl border border-dashed border-base-300 p-3">
                  <span class="text-xs font-semibold uppercase tracking-wide opacity-60">
                    Checklist (opcional)
                  </span>

                  <ul :if={@capture_tasks != []} class="space-y-1">
                    <li
                      :for={{task, index} <- Enum.with_index(@capture_tasks)}
                      class="flex items-center gap-2"
                    >
                      <span class="size-4 shrink-0 rounded-full border-2 border-base-content/40" />
                      <span class="flex-1 text-sm">{task.title}</span>
                      <span class="shrink-0 text-xs font-semibold opacity-60">
                        {task.store_points} pts
                      </span>
                      <button
                        type="button"
                        phx-click="remove_capture_task"
                        phx-value-index={index}
                        class="shrink-0 opacity-50 hover:opacity-100"
                        aria-label="Remover subitem"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </li>
                  </ul>

                  <div class="flex items-end gap-2">
                    <div class="flex-1">
                      <.input
                        type="text"
                        name="task_draft"
                        label="Novo subitem"
                        value={@capture_task_draft}
                        placeholder="Ex: Separar os materiais"
                        onkeydown="if(event.key === 'Enter') event.preventDefault();"
                        phx-keydown="add_capture_task"
                        phx-key="Enter"
                      />
                    </div>
                    <div class="w-20">
                      <.input
                        type="number"
                        name="task_points_draft"
                        label="Pontos"
                        value={@capture_task_points_draft}
                        min="0"
                      />
                    </div>
                    <div class="fieldset mb-2">
                      <label>
                        <span class="label mb-1 invisible">Adicionar</span>
                        <button
                          type="button"
                          phx-click="add_capture_task"
                          class="btn btn-soft btn-sm rounded-full px-4"
                        >
                          Adicionar
                        </button>
                      </label>
                    </div>
                  </div>
                </div>
              </div>
            </form>
          </div>

          <div id="loose-captures" class="space-y-2">
            <div class="flex items-center justify-between gap-3 px-1">
              <h3 class="flex items-center gap-2 text-xs font-bold uppercase tracking-wide opacity-50">
                Capturas soltas
              </h3>
              <span
                :if={@loose_captures != []}
                class="rounded-full bg-error/10 px-2.5 py-0.5 text-xs font-bold text-error"
              >
                {length(@loose_captures)}
              </span>
            </div>

            <p :if={@loose_captures == []} class="px-1 text-sm opacity-50">
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
                    :if={activity.kind == :evento}
                    phx-click="open_snooze"
                    phx-value-id={activity.id}
                    class="btn btn-ghost btn-sm"
                    title="Reagendar — muda o dia marcado do evento"
                  >
                    <.icon name="hero-calendar-days" class="size-4 opacity-60" />
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
              class="min-h-40 space-y-2 overflow-y-auto rounded-2xl border border-dashed border-base-300 px-3 py-2 md:h-[64rem]"
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
              class="min-h-40 space-y-2 overflow-y-auto rounded-2xl border border-dashed border-base-300 px-3 py-2 md:h-[64rem]"
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
            <h3 class="text-xs font-bold uppercase tracking-wide text-success opacity-70">Feito</h3>
            <Components.drop_zone
              id="today-feito"
              drag_group="today-flow"
              mode="move"
              event="move_flow"
              value="feito"
              class="min-h-40 space-y-2 overflow-y-auto rounded-2xl border border-dashed border-success/40 bg-success/5 px-3 py-2 md:h-[64rem]"
            >
              <p :if={@feito_activities == []} class="py-4 text-center text-xs opacity-40">
                Nada concluído ainda
              </p>
              <Components.draggable
                :for={activity <- @feito_activities}
                id={"activity-drag-#{activity.id}"}
                drag_id={activity.id}
              >
                <Components.activity_card activity={activity}>
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
              </Components.draggable>
            </Components.drop_zone>
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
      :if={is_nil(@activity.habit_id)}
      phx-click="open_snooze"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title={
        if @activity.kind == :evento,
          do: "Reagendar — muda o dia marcado do evento",
          else: "Adiar — some daqui até a data escolhida"
      }
    >
      <.icon
        name={if @activity.kind == :evento, do: "hero-calendar-days", else: "hero-clock"}
        class="size-4 text-info"
      />
    </button>
    <button
      phx-click="discard_activity"
      phx-value-id={@activity.id}
      class="btn btn-ghost btn-xs"
      title="Descartar"
    >
      <.icon name="hero-trash" class="size-4 text-error" />
    </button>
    """
  end

  attr :activity, :map, required: true

  defp snooze_modal(assigns) do
    assigns =
      assigns
      |> assign(:min_date, Date.add(Date.utc_today(), 1))
      |> assign(:event?, assigns.activity.kind == :evento)

    ~H"""
    <div id="snooze-modal">
      <div class="modal modal-open" phx-window-keydown="close_snooze_modal" phx-key="Escape">
        <div class="modal-box max-w-sm rounded-3xl">
          <h2 class="text-lg font-bold tracking-tight">
            {if @event?, do: "Reagendar evento", else: "Adiar atividade"}
          </h2>
          <p class="mt-1 text-sm opacity-70">
            {if @event? do
              ~s("#{@activity.title}" muda de dia — o card só aparece na Tela do dia na nova data escolhida.)
            else
              ~s("#{@activity.title}" some da Tela do dia até a data escolhida — reaparece sozinha nesse dia.)
            end}
          </p>

          <form id="snooze-form" phx-submit="confirm_snooze" class="mt-4 space-y-4">
            <.input
              type="date"
              name="until"
              label={if @event?, do: "Nova data", else: "Adiar até"}
              value={if @event?, do: Date.to_iso8601(@activity.logical_date), else: ""}
              min={if @event?, do: nil, else: Date.to_iso8601(@min_date)}
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
                {if @event?, do: "Reagendar", else: "Adiar"}
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
