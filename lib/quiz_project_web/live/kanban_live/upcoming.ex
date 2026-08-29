defmodule QuizProjectWeb.KanbanLive.Upcoming do
  @moduledoc """
  Pré-visualização dos próximos dias — hábitos ativos devidos e atividades
  adiadas que reaparecem em cada dia (ver `Priorities.snooze_activity/3`).
  Só orientação (ex: "por que esse hábito não apareceu hoje", "o que vem
  por aí"). Não gera nenhuma `Activity` nova (isso só acontece na Tela do
  dia, `KanbanLive`, no dia em que é devido/adiado de verdade) — mas o
  hábito em si pode ser aberto, ter a frequência editada (pra sempre, ou só
  a partir daquele dia), ter aquele dia específico pulado/renomeado, ser
  arquivado ou excluído daqui, via `HabitModal`; uma atividade adiada só
  pode ter o adiamento cancelado daqui (volta pra Tela do dia na hora). Ver
  `Priorities.upcoming_habit_schedule/2`.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.HabitModal
  alias QuizProjectWeb.PrioritiesLive.Components

  @days_ahead 7

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Próximos dias", modal_habit_id: nil, modal_habit_date: nil)
     |> load_schedule()}
  end

  @impl true
  def handle_event("open_habit", %{"id" => id, "date" => date}, socket) do
    {:noreply, assign(socket, modal_habit_id: id, modal_habit_date: Date.from_iso8601!(date))}
  end

  @impl true
  def handle_event("close_habit_modal", _params, socket) do
    {:noreply, socket |> assign(modal_habit_id: nil, modal_habit_date: nil) |> load_schedule()}
  end

  @impl true
  def handle_event("cancel_snooze", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      Priorities.clear_activity_snooze(activity, user)
    end

    {:noreply, socket |> put_flash(:info, "Adiamento cancelado.") |> load_schedule()}
  end

  @impl true
  def handle_info({:kanban_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  def handle_info({:habit_deleted, _id}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Hábito excluído.")
     |> assign(modal_habit_id: nil, modal_habit_date: nil)
     |> load_schedule()}
  end

  @impl true
  def handle_info({:habit_schedule_changed}, socket) do
    {:noreply,
     socket
     |> assign(modal_habit_id: nil, modal_habit_date: nil)
     |> load_schedule()}
  end

  defp load_schedule(socket) do
    assign(socket,
      schedule: Priorities.upcoming_habit_schedule(socket.assigns.current_user, @days_ahead)
    )
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
          <h1 class="text-2xl font-bold tracking-tight">Próximos dias</h1>
          <p class="text-sm opacity-70">
            Hábitos ativos devidos e atividades adiadas nos próximos {length(@schedule)} dias —
            só pré-visualização. Clique num hábito pra editar a frequência (pra sempre ou só dali
            pra frente), pular/renomear esse dia, arquivar ou excluir; clique numa atividade
            adiada pra cancelar o adiamento e trazê-la de volta pra Tela do dia agora.
          </p>
        </div>

        <Components.kanban_sub_nav active={:upcoming} />

        <div
          :for={day <- @schedule}
          id={"upcoming-day-#{Date.to_iso8601(day.date)}"}
          class="space-y-2"
        >
          <h2 class="flex items-baseline gap-2 text-sm font-bold uppercase tracking-wide opacity-60">
            {weekday_label(day.date)}
            <span class="text-xs font-semibold normal-case opacity-50">
              {Calendar.strftime(day.date, "%d/%m")}
            </span>
          </h2>

          <p :if={day.habits == [] and day.snoozed == []} class="text-xs opacity-40">
            Nada previsto
          </p>

          <div :if={day.habits != [] or day.snoozed != []} class="flex flex-wrap gap-2">
            <button
              :for={entry <- day.habits}
              type="button"
              phx-click="open_habit"
              phx-value-id={entry.habit.id}
              phx-value-date={Date.to_iso8601(day.date)}
              class="flex items-center gap-1.5 rounded-full border border-base-300 bg-base-100 px-3 py-1.5 text-sm font-semibold transition hover:border-primary"
            >
              <span class={[
                "size-2 shrink-0 rounded-full",
                elem(Components.category_colors(entry.habit.item.category_id), 1)
              ]}></span>
              {entry.title}
            </button>

            <button
              :for={activity <- day.snoozed}
              type="button"
              phx-click="cancel_snooze"
              phx-value-id={activity.id}
              data-confirm="Cancelar o adiamento? Volta a aparecer na Tela do dia agora."
              title="Adiada — clique pra cancelar o adiamento"
              class="flex items-center gap-1.5 rounded-full border border-dashed border-info/50 bg-info/5 px-3 py-1.5 text-sm font-semibold text-info transition hover:border-info"
            >
              <.icon name="hero-clock" class="size-3.5" />
              <span class={[
                "size-2 shrink-0 rounded-full",
                elem(Components.category_colors(activity.item.category_id), 1)
              ]}></span>
              {activity.title}
            </button>
          </div>
        </div>
      </div>

      <.live_component
        :if={@modal_habit_id}
        module={HabitModal}
        id={"habit-modal-#{@modal_habit_id}-#{Date.to_iso8601(@modal_habit_date)}"}
        habit_id={@modal_habit_id}
        occurrence_date={@modal_habit_date}
        current_user={@current_user}
      />
    </Layouts.app>
    """
  end

  defp weekday_label(date) do
    case Date.day_of_week(date) do
      1 -> "Segunda"
      2 -> "Terça"
      3 -> "Quarta"
      4 -> "Quinta"
      5 -> "Sexta"
      6 -> "Sábado"
      7 -> "Domingo"
    end
  end
end
