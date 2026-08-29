defmodule QuizProjectWeb.KanbanLive.Calendar do
  @moduledoc """
  Calendário mensal: instância de hábito e evento aparecem pelo dia marcado
  (`logical_date` — evento independente de já ter sido resolvido ou não, é
  a data real do compromisso), o resto (atividade comum presa a item ou
  captura solta) aparece pelo dia em que foi resolvida (`resolved_date`) —
  ver `Priorities.list_activities_between/3`. Navega livremente entre
  meses passados e futuros; um dia futuro pode não ter nada resolvido
  ainda, mas mostra os eventos já marcados pra ele.

  Só consulta: sem título clicável, sem editar nada, sem checklist nem
  gerenciar hábito (isso é papel da Tela do dia/`ActivityModal`). A única
  ação daqui é corrigir o desfecho de algo já resolvido — `Priorities.correct_activity_status/3`,
  que não mexe em `resolved_date` nem reabre a atividade, só troca entre
  concluída/não cumprida sem tirá-la do dia em que está.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProject.Priorities.Clock
  alias QuizProjectWeb.PrioritiesLive.Components

  @weekday_headers ~w(Seg Ter Qua Qui Sex Sáb Dom)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Calendário", weekday_headers: @weekday_headers)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month = parse_month(params["month"]) || Date.beginning_of_month(Clock.today())

    selected_date =
      case parse_date(params["date"]) do
        nil -> if same_month?(month, Clock.today()), do: Clock.today(), else: nil
        date -> date
      end

    {:noreply,
     socket
     |> assign(month: month, selected_date: selected_date)
     |> load_month()}
  end

  @impl true
  def handle_event("correct_status", %{"id" => id, "status" => status}, socket) do
    user = socket.assigns.current_user
    status = String.to_existing_atom(status)

    with {:ok, activity} <- Priorities.get_activity(id, user) do
      Priorities.correct_activity_status(activity, status, user)
    end

    {:noreply, load_month(socket)}
  end

  defp load_month(socket) do
    grid_start = grid_start(socket.assigns.month)
    grid_end = grid_end(socket.assigns.month)

    by_date =
      socket.assigns.current_user
      |> Priorities.list_activities_between(grid_start, grid_end)
      |> Enum.group_by(&activity_date/1)

    assign(socket,
      weeks: Date.range(grid_start, grid_end) |> Enum.chunk_every(7),
      by_date: by_date,
      selected_activities: Map.get(by_date, socket.assigns.selected_date, [])
    )
  end

  defp activity_date(%{
         habit_id: habit_id,
         kind: kind,
         logical_date: logical_date,
         resolved_date: resolved_date
       }) do
    if habit_id || kind == :evento, do: logical_date, else: resolved_date
  end

  defp grid_start(month) do
    start = Date.beginning_of_month(month)
    Date.add(start, -(Date.day_of_week(start) - 1))
  end

  defp grid_end(month) do
    finish = Date.end_of_month(month)
    Date.add(finish, 7 - Date.day_of_week(finish))
  end

  defp same_month?(%Date{year: y, month: m}, %Date{year: y, month: m}), do: true
  defp same_month?(_a, _b), do: false

  defp parse_month(nil), do: nil

  defp parse_month(str) do
    case Date.from_iso8601("#{str}-01") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp month_param(month), do: Calendar.strftime(month, "%Y-%m")

  defp day_summary(activities) do
    %{
      done: Enum.count(activities, &(&1.status == :concluida)),
      not_done: Enum.count(activities, &(&1.status == :nao_cumprida)),
      upcoming: Enum.count(activities, &(&1.kind == :evento and &1.flow != :feito))
    }
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

  # `Calendar.strftime/2` não traduz `%B` — nomes de mês saem em inglês.
  defp month_label(%Date{month: month, year: year}) do
    name =
      case month do
        1 -> "Janeiro"
        2 -> "Fevereiro"
        3 -> "Março"
        4 -> "Abril"
        5 -> "Maio"
        6 -> "Junho"
        7 -> "Julho"
        8 -> "Agosto"
        9 -> "Setembro"
        10 -> "Outubro"
        11 -> "Novembro"
        12 -> "Dezembro"
      end

    "#{name} de #{year}"
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
          <h1 class="text-2xl font-bold tracking-tight">Calendário</h1>
          <p class="text-sm opacity-70">
            Hábito e evento pelo dia marcado, o resto pelo dia em que foi resolvido — navegue por
            qualquer mês, passado ou futuro. Só consulta: dá pra corrigir se ficou marcado como
            concluída/não cumprida por engano, mais nada.
          </p>
        </div>

        <Components.kanban_sub_nav active={:calendar} />

        <div class="space-y-4 rounded-3xl border border-base-300 bg-base-100 p-4">
          <div class="flex items-center justify-between gap-3">
            <.link
              patch={
                ~p"/today/calendar?#{[month: month_param(Date.add(Date.beginning_of_month(@month), -1))]}"
              }
              class="btn btn-ghost btn-sm rounded-full"
            >
              <.icon name="hero-chevron-left" class="size-4" />
            </.link>

            <h2 class="text-sm font-bold uppercase tracking-wide opacity-70">
              {month_label(@month)}
            </h2>

            <.link
              patch={
                ~p"/today/calendar?#{[month: month_param(Date.add(Date.end_of_month(@month), 1))]}"
              }
              class="btn btn-ghost btn-sm rounded-full"
            >
              <.icon name="hero-chevron-right" class="size-4" />
            </.link>
          </div>

          <div class="grid grid-cols-7 gap-1 text-center text-xs font-semibold uppercase opacity-50">
            <span :for={label <- @weekday_headers}>{label}</span>
          </div>

          <div class="space-y-1">
            <div :for={week <- @weeks} class="grid grid-cols-7 gap-1">
              <.day_cell
                :for={day <- week}
                day={day}
                month={@month}
                selected?={day == @selected_date}
                summary={day_summary(Map.get(@by_date, day, []))}
              />
            </div>
          </div>
        </div>

        <div class="space-y-3 rounded-3xl border border-base-300 bg-base-100 p-4">
          <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">
            {if @selected_date,
              do: "#{weekday_label(@selected_date)} — #{Calendar.strftime(@selected_date, "%d/%m")}",
              else: "Nenhum dia selecionado"}
          </h2>

          <p :if={is_nil(@selected_date)} class="text-sm opacity-50">
            Escolha um dia no calendário.
          </p>

          <p :if={@selected_date && @selected_activities == []} class="text-sm opacity-50">
            Nada registrado nesse dia.
          </p>

          <div :if={@selected_activities != []} class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <Components.activity_card
              :for={activity <- @selected_activities}
              activity={activity}
              clickable_title?={false}
            >
              <:actions :if={activity.flow == :feito}>
                <.correct_status_buttons activity={activity} />
              </:actions>
            </Components.activity_card>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :activity, :map, required: true

  defp correct_status_buttons(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="correct_status"
      phx-value-id={@activity.id}
      phx-value-status="concluida"
      class={[
        "btn btn-xs rounded-full",
        if(@activity.status == :concluida, do: "btn-success", else: "btn-ghost")
      ]}
    >
      <.icon name="hero-check" class="size-3.5" /> Concluída
    </button>
    <button
      type="button"
      phx-click="correct_status"
      phx-value-id={@activity.id}
      phx-value-status="nao_cumprida"
      class={[
        "btn btn-xs rounded-full",
        if(@activity.status == :nao_cumprida, do: "btn-warning", else: "btn-ghost")
      ]}
    >
      <.icon name="hero-x-mark" class="size-3.5" /> Não cumprida
    </button>
    """
  end

  attr :day, :any, required: true
  attr :month, :any, required: true
  attr :selected?, :boolean, required: true
  attr :summary, :map, required: true

  defp day_cell(assigns) do
    assigns = assign(assigns, :outside_month?, assigns.day.month != assigns.month.month)

    ~H"""
    <.link
      patch={~p"/today/calendar?#{[month: month_param(@month), date: Date.to_iso8601(@day)]}"}
      class={[
        "flex flex-col items-center gap-0.5 rounded-xl border p-1.5 text-xs transition",
        @selected? && "border-primary bg-primary/10",
        !@selected? && "border-transparent hover:border-base-300",
        @outside_month? && "opacity-40"
      ]}
    >
      <span class="font-semibold">{@day.day}</span>
      <span class="flex gap-1">
        <span :if={@summary.done > 0} class="font-bold text-success">✓{@summary.done}</span>
        <span :if={@summary.not_done > 0} class="font-bold text-warning">✗{@summary.not_done}</span>
        <span :if={@summary.upcoming > 0} class="font-bold text-info">•{@summary.upcoming}</span>
      </span>
    </.link>
    """
  end
end
