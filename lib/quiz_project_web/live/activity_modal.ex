defmodule QuizProjectWeb.ActivityModal do
  @moduledoc """
  Detalhe de uma atividade do Kanban: título, descrição opcional e checklist
  de subitens — o que não cabe no card compacto da Tela do dia. Quando a
  atividade é uma instância de hábito (`activity.habit_id` presente), ganha
  também uma seção "Hábito" (streak, frequência, arquivar) — hábito não tem
  mais tela própria (não é `Item`), então é aqui que ele é gerenciado.

  Fechar (✕, backdrop, Escape) não tem `phx-target`: sobe pro LiveView pai de
  propósito, que é quem decide parar de renderizar este componente — mesmo
  padrão do `PrioritiesLive.ItemModal`.
  """
  use QuizProjectWeb, :live_component

  alias QuizProject.Priorities
  alias QuizProjectWeb.PrioritiesLive.Components

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:habit_frequency_form_value, fn -> nil end)
     |> load_activity(assigns.activity_id)}
  end

  @impl true
  def handle_event("update_activity", %{"title" => title, "notes" => notes}, socket) do
    user = socket.assigns.current_user
    title = String.trim(title)

    if title == "" do
      {:noreply, notify_flash(socket, :error, "O título não pode ficar em branco.")}
    else
      case Priorities.update_activity(
             socket.assigns.activity,
             %{title: title, notes: notes},
             user
           ) do
        {:ok, _} ->
          {:noreply,
           socket |> notify_flash(:info, "Salvo.") |> load_activity(socket.assigns.activity.id)}

        _ ->
          {:noreply, notify_flash(socket, :error, "Não foi possível salvar.")}
      end
    end
  end

  @impl true
  def handle_event("create_task", %{"title" => title}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, socket}
    else
      {:ok, _} =
        Priorities.create_activity_task(
          socket.assigns.activity,
          title,
          socket.assigns.current_user
        )

      {:noreply, load_activity(socket, socket.assigns.activity.id)}
    end
  end

  @impl true
  def handle_event("toggle_task", %{"id" => id}, socket) do
    task = Enum.find(socket.assigns.tasks, &(&1.id == id))

    if task do
      {:ok, _} =
        Priorities.toggle_activity_task(
          task,
          socket.assigns.activity,
          socket.assigns.current_user
        )
    end

    {:noreply, load_activity(socket, socket.assigns.activity.id)}
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Enum.find(socket.assigns.tasks, &(&1.id == id))

    if task do
      {:ok, _} =
        Priorities.delete_activity_task(
          task,
          socket.assigns.activity,
          socket.assigns.current_user
        )
    end

    {:noreply, load_activity(socket, socket.assigns.activity.id)}
  end

  @impl true
  def handle_event("habit_frequency_form_change", %{"frequency" => freq}, socket) do
    {:noreply, assign(socket, habit_frequency_form_value: freq)}
  end

  @impl true
  def handle_event("set_habit_frequency", params, socket) do
    user = socket.assigns.current_user
    attrs = build_habit_frequency_attrs(params)

    case Priorities.set_habit_frequency(socket.assigns.activity.habit, attrs, user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notify_flash(:info, "Frequência salva.")
         |> assign(habit_frequency_form_value: nil)
         |> load_activity(socket.assigns.activity.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar a frequência.")}
    end
  end

  @impl true
  def handle_event("toggle_archive_habit", _params, socket) do
    habit = socket.assigns.activity.habit
    user = socket.assigns.current_user

    result =
      if habit.archived_at,
        do: Priorities.unarchive_habit(habit, user),
        else: Priorities.archive_habit(habit, user)

    case result do
      {:ok, _} -> {:noreply, load_activity(socket, socket.assigns.activity.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível atualizar o hábito.")}
    end
  end

  @impl true
  def handle_event("delete_habit", _params, socket) do
    habit = socket.assigns.activity.habit
    user = socket.assigns.current_user

    case Priorities.delete_habit(habit, user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notify_flash(:info, "Hábito excluído.")
         |> load_activity(socket.assigns.activity.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível excluir o hábito.")}
    end
  end

  defp build_habit_frequency_attrs(%{"frequency" => "weekly"} = params) do
    %{frequency: :weekly, weekdays: parse_int_list(params["weekdays"]), month_days: []}
  end

  defp build_habit_frequency_attrs(%{"frequency" => "monthly"} = params) do
    %{frequency: :monthly, weekdays: [], month_days: parse_int_list(params["month_days"])}
  end

  defp build_habit_frequency_attrs(_params) do
    %{frequency: :daily, weekdays: [], month_days: []}
  end

  defp parse_int_list(nil), do: []
  defp parse_int_list(values) when is_list(values), do: Enum.map(values, &String.to_integer/1)

  # `put_flash/3` num LiveComponent só grava no `assigns.flash` isolado do
  # componente, que nunca é renderizado — quem mostra `@flash` é o
  # `Layouts.app` do LiveView pai. Por isso o flash sai daqui como mensagem
  # pro processo do LiveView, mesmo padrão do `PrioritiesLive.ItemModal`.
  defp notify_flash(socket, kind, message) do
    send(self(), {:kanban_flash, kind, message})
    socket
  end

  defp load_activity(socket, id) do
    user = socket.assigns.current_user
    {:ok, activity} = Priorities.get_activity(id, user)

    assign(socket,
      activity: activity,
      tasks: Priorities.list_activity_tasks(activity.id),
      habit_streak: if(activity.habit_id, do: Priorities.habit_streak(activity.habit_id))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="modal modal-open" phx-window-keydown="close_activity_modal" phx-key="Escape">
        <div class="modal-box flex max-h-[85vh] max-w-lg flex-col overflow-hidden rounded-3xl p-0">
          <div class="flex shrink-0 items-center justify-between gap-3 border-b border-base-300 px-6 pb-4 pt-6">
            <h1 class="text-xl font-bold tracking-tight">{@activity.title}</h1>
            <button
              type="button"
              phx-click="close_activity_modal"
              class="btn btn-sm btn-circle btn-ghost shrink-0"
              aria-label="Fechar"
            >
              ✕
            </button>
          </div>

          <div class="flex-1 space-y-6 overflow-y-auto p-6">
            <form
              id="update-activity-form"
              phx-submit="update_activity"
              phx-target={@myself}
              class="space-y-3"
            >
              <.input type="text" name="title" label="Título" value={@activity.title} required />
              <.input
                type="textarea"
                name="notes"
                label="Descrição (opcional)"
                value={@activity.notes}
                rows="3"
                placeholder="Mais contexto sobre essa atividade..."
              />
              <div class="flex justify-end">
                <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
                  Salvar
                </button>
              </div>
            </form>

            <div :if={@activity.habit_id} class="border-t border-base-200 pt-4">
              <Components.habit_section
                habit={@activity.habit}
                myself={@myself}
                habit_streak={@habit_streak}
                habit_frequency_form_value={@habit_frequency_form_value}
                occurrence_date={@activity.logical_date}
              />
            </div>

            <div class="space-y-3 border-t border-base-200 pt-4">
              <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Checklist</h2>

              <ul :if={@tasks != []} class="space-y-1">
                <li :for={task <- @tasks} class="group flex items-center gap-2">
                  <button
                    id={"toggle-activity-task-#{task.id}"}
                    phx-click="toggle_task"
                    phx-value-id={task.id}
                    phx-target={@myself}
                    class="flex flex-1 items-center gap-2 text-left text-sm"
                  >
                    <.icon
                      name={if task.done, do: "hero-check-circle-solid", else: "hero-circle"}
                      class={["size-4 shrink-0", task.done && "text-primary"]}
                    />
                    <span class={task.done && "opacity-50 line-through"}>{task.title}</span>
                  </button>
                  <button
                    id={"delete-activity-task-#{task.id}"}
                    phx-click="delete_task"
                    phx-value-id={task.id}
                    phx-target={@myself}
                    class="shrink-0 opacity-0 transition group-hover:opacity-50 hover:opacity-100!"
                    aria-label="Excluir subitem"
                    title="Excluir subitem"
                  >
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                </li>
              </ul>

              <p :if={@tasks == []} class="text-xs opacity-60">Nenhum subitem ainda.</p>

              <form
                id="create-activity-task-form"
                phx-submit="create_task"
                phx-target={@myself}
                class="flex items-end gap-2"
              >
                <div class="flex-1">
                  <.input
                    type="text"
                    name="title"
                    label="Novo subitem"
                    value=""
                    placeholder="Ex: Separar os materiais"
                  />
                </div>
                <div class="fieldset mb-2">
                  <label>
                    <span class="label mb-1 invisible">Adicionar</span>
                    <button type="submit" class="btn btn-soft btn-sm rounded-full px-4">
                      Adicionar
                    </button>
                  </label>
                </div>
              </form>
            </div>
          </div>
        </div>

        <button
          type="button"
          phx-click="close_activity_modal"
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
