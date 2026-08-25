defmodule QuizProjectWeb.KanbanLive.Upcoming do
  @moduledoc """
  Pré-visualização dos hábitos ativos devidos nos próximos dias — só
  orientação (ex: "por que esse hábito não apareceu hoje", "o que vem por
  aí"). Não gera nenhuma `Activity` (isso só acontece na Tela do dia,
  `KanbanLive`, no dia em que o hábito é devido de verdade) — mas o hábito
  em si pode ser aberto, ter a frequência editada (pra sempre, ou só a
  partir daquele dia), ter aquele dia específico pulado/renomeado, ser
  arquivado ou excluído daqui, via `HabitModal`. Ver
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
            Hábitos ativos devidos nos próximos {length(@schedule)} dias — só pré-visualização,
            nada aqui vira atividade antes do dia chegar. Clique num hábito pra editar a
            frequência (pra sempre ou só dali pra frente), pular/renomear esse dia, arquivar ou
            excluir.
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

          <p :if={day.habits == []} class="text-xs opacity-40">Nada previsto</p>

          <div :if={day.habits != []} class="flex flex-wrap gap-2">
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
