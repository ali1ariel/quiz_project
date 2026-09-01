defmodule QuizProjectWeb.PrioritiesLive.History do
  @moduledoc """
  Histórico de categorias e prioridades, agrupado por dia (mais recente
  primeiro) — `Priorities.list_priorities_history/1`. Log de atividade não
  entra aqui, esse já tem lugar próprio na seção "Logs do dia" do
  Calendário do Kanban (`QuizProjectWeb.KanbanLive.Calendar`).

  Cada dia é um acordeon minimizado por padrão (`<details>` nativo, sem
  estado no servidor) — expandir mostra os eventos daquele dia: categoria
  e prioridade criadas, e toda manutenção nelas (renomear, arquivar, tag,
  tier, checklist, ...), na mesma linha de bullet + hora + acontecimento
  do "Logs do dia" do Calendário.

  Só consulta: nenhuma ação daqui, nada clicável.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.PrioritiesLive.Components

  @impl true
  def mount(_params, _session, socket) do
    days =
      socket.assigns.current_user
      |> Priorities.list_priorities_history()
      |> group_by_day()

    {:ok, assign(socket, page_title: "Histórico", days: days)}
  end

  defp group_by_day(logs) do
    logs
    |> Enum.group_by(& &1.logical_date)
    |> Enum.sort_by(fn {date, _logs} -> date end, {:desc, Date})
  end

  defp weekday_label(date) do
    case Date.day_of_week(date) do
      1 -> "Segunda-feira"
      2 -> "Terça-feira"
      3 -> "Quarta-feira"
      4 -> "Quinta-feira"
      5 -> "Sexta-feira"
      6 -> "Sábado"
      7 -> "Domingo"
    end
  end

  # `Clock`/`inserted_at` gravam em UTC — mesmo deslocamento fixo de
  # Brasília (ver `QuizProject.Priorities.Clock`) só pra exibir a hora. Sem
  # data junto: o dia já está no cabeçalho do acordeon.
  defp local_time(datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%H:%M:%S")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:priorities}
    >
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Histórico</h1>
          <p class="text-sm opacity-70">
            Categorias e prioridades criadas e mantidas, um acordeon por dia — mais recente
            primeiro. Abra um dia pra ver o que aconteceu nele.
          </p>
        </div>

        <Components.sub_nav active={:history} />

        <p
          :if={@days == []}
          class="rounded-3xl border border-dashed border-base-300 p-10 text-center text-sm opacity-50"
        >
          Nada registrado ainda.
        </p>

        <div :if={@days != []} id="priorities-history-days" class="space-y-2">
          <details
            :for={{date, logs} <- @days}
            class="collapse collapse-arrow rounded-2xl border border-base-300 bg-base-100"
          >
            <summary class="collapse-title flex items-center gap-2 text-sm font-semibold">
              {weekday_label(date)} — {Calendar.strftime(date, "%d/%m/%Y")}
              <span class="rounded-full bg-base-200 px-2 py-0.5 text-xs font-bold opacity-70">
                {length(logs)}
              </span>
            </summary>

            <div class="collapse-content">
              <ul class="space-y-2">
                <li :for={log <- logs} class="flex items-baseline gap-2 text-sm">
                  <span class="shrink-0 opacity-40">•</span>
                  <span class="shrink-0 font-mono text-xs opacity-50">
                    {local_time(log.inserted_at)}
                  </span>
                  <span class="opacity-90">{log.message}</span>
                </li>
              </ul>
            </div>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
