defmodule QuizProjectWeb.HabitModal do
  @moduledoc """
  Edição de um hábito direto (sem passar por nenhuma `Activity` de um dia
  específico) — aberto pela tela "Próximos dias"
  (`KanbanLive.Upcoming`), onde um hábito futuro ainda não tem instância
  gerada pra abrir via `ActivityModal`. Mesma seção "Hábito" compartilhada
  com `ActivityModal` (`Components.habit_section/1`), mas aqui com
  `show_scope_choice?`/`allow_occurrence_edit?` ligados: dá pra escolher
  entre mudar a regra toda, só a partir de `occurrence_date`, ou só aquele
  dia (pular/renomear), já que aqui a data clicada nunca tem `Activity`
  ainda pra editar direto.

  Fechar (✕, backdrop, Escape) não tem `phx-target`: sobe pro LiveView pai,
  mesmo padrão de `ActivityModal`/`PrioritiesLive.ItemModal`.
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
     |> load_habit(assigns.habit_id)}
  end

  @impl true
  def handle_event("habit_frequency_form_change", %{"frequency" => freq}, socket) do
    {:noreply, assign(socket, habit_frequency_form_value: freq)}
  end

  @impl true
  def handle_event("set_habit_frequency", %{"scope" => "from_here"} = params, socket) do
    habit = socket.assigns.habit
    user = socket.assigns.current_user
    attrs = build_habit_frequency_attrs(params)

    case Priorities.change_habit_frequency_from(
           habit,
           socket.assigns.occurrence_date,
           attrs,
           user
         ) do
      {:ok, _novo_habit} ->
        notify_flash(
          socket,
          :info,
          "Frequência atualizada a partir de #{format_date(socket.assigns.occurrence_date)}."
        )

        send(self(), {:habit_schedule_changed})
        {:noreply, socket}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar a frequência.")}
    end
  end

  def handle_event("set_habit_frequency", params, socket) do
    user = socket.assigns.current_user
    attrs = build_habit_frequency_attrs(params)

    case Priorities.set_habit_frequency(socket.assigns.habit, attrs, user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notify_flash(:info, "Frequência salva.")
         |> assign(habit_frequency_form_value: nil)
         |> load_habit(socket.assigns.habit.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar a frequência.")}
    end
  end

  @impl true
  def handle_event("toggle_archive_habit", _params, socket) do
    habit = socket.assigns.habit
    user = socket.assigns.current_user

    result =
      if habit.archived_at,
        do: Priorities.unarchive_habit(habit, user),
        else: Priorities.archive_habit(habit, user)

    case result do
      {:ok, _} -> {:noreply, load_habit(socket, habit.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível atualizar o hábito.")}
    end
  end

  @impl true
  def handle_event("delete_habit", _params, socket) do
    user = socket.assigns.current_user

    case Priorities.delete_habit(socket.assigns.habit, user) do
      {:ok, _} ->
        send(self(), {:habit_deleted, socket.assigns.habit.id})
        {:noreply, socket}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível excluir o hábito.")}
    end
  end

  @impl true
  def handle_event("save_occurrence_override", params, socket) do
    habit = socket.assigns.habit
    user = socket.assigns.current_user
    date = socket.assigns.occurrence_date

    attrs = %{
      skipped: Map.get(params, "skipped") == "true",
      title: blank_to_nil(Map.get(params, "title", ""))
    }

    case Priorities.set_habit_occurrence_override(habit, date, attrs, user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notify_flash(:info, "Exceção salva para #{format_date(date)}.")
         |> load_habit(habit.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar a exceção.")}
    end
  end

  @impl true
  def handle_event("clear_occurrence_override", _params, socket) do
    habit = socket.assigns.habit
    user = socket.assigns.current_user
    date = socket.assigns.occurrence_date

    case Priorities.clear_habit_occurrence_override(habit, date, user) do
      :ok ->
        {:noreply, socket |> notify_flash(:info, "Exceção removida.") |> load_habit(habit.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível remover a exceção.")}
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

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_date(date), do: Calendar.strftime(date, "%d/%m")

  # `put_flash/3` num LiveComponent só grava no `assigns.flash` isolado do
  # componente, que nunca é renderizado — mesmo padrão de `ActivityModal`.
  defp notify_flash(socket, kind, message) do
    send(self(), {:kanban_flash, kind, message})
    socket
  end

  defp load_habit(socket, id) do
    user = socket.assigns.current_user
    {:ok, habit} = Priorities.get_habit(id, user)
    date = socket.assigns.occurrence_date

    assign(socket,
      habit: habit,
      habit_streak: Priorities.habit_streak(habit.id),
      occurrence_override: Priorities.get_habit_occurrence_override(habit.id, date)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="modal modal-open" phx-window-keydown="close_habit_modal" phx-key="Escape">
        <div class="modal-box flex max-h-[85vh] max-w-lg flex-col overflow-hidden rounded-3xl p-0">
          <div class="flex shrink-0 items-center justify-between gap-3 border-b border-base-300 px-6 pb-4 pt-6">
            <h1 class="text-xl font-bold tracking-tight">{@habit.title}</h1>
            <button
              type="button"
              phx-click="close_habit_modal"
              class="btn btn-sm btn-circle btn-ghost shrink-0"
              aria-label="Fechar"
            >
              ✕
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-6">
            <Components.habit_section
              habit={@habit}
              myself={@myself}
              habit_streak={@habit_streak}
              habit_frequency_form_value={@habit_frequency_form_value}
              occurrence_date={@occurrence_date}
              show_scope_choice?={true}
              allow_occurrence_edit?={true}
              occurrence_override={@occurrence_override}
            />
          </div>
        </div>

        <button type="button" phx-click="close_habit_modal" class="modal-backdrop" aria-label="Fechar">
          Fechar
        </button>
      </div>
    </div>
    """
  end
end
