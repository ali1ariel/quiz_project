defmodule QuizProjectWeb.WishStoreLive.Wallet do
  @moduledoc """
  Carteira de pontos: saldo atual e o extrato completo de créditos
  (concluir atividade/subitem/hábito, prioridade chegar em 100%) e estornos
  (desfazer qualquer um desses), mais recente primeiro —
  `Priorities.wallet_balance/1` e `Priorities.list_wallet_entries/1`.

  Tela raiz da Wish Store (`/wish-store`) — hoje a única aba; futuras telas
  da loja (resgate de pontos por recompensas) entram como abas irmãs, ver
  `QuizProjectWeb.WishStoreLive.Components.sub_nav/1`.

  Só consulta: nenhum lançamento é criado ou editado por aqui, sempre pelas
  actions de negócio que já mexem em atividade/checklist/progresso.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.WishStoreLive.Components

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       page_title: "Wish Store",
       balance: Priorities.wallet_balance(user),
       entries: Priorities.list_wallet_entries(user)
     )}
  end

  # `Clock`/`inserted_at` gravam em UTC — mesmo deslocamento fixo de
  # Brasília (ver `QuizProject.Priorities.Clock`) só pra exibir a hora.
  defp local_datetime(datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%d/%m/%Y %H:%M")
  end

  defp source_label(:activity), do: "Atividade"
  defp source_label(:activity_task), do: "Checklist"
  defp source_label(:item), do: "Prioridade"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:wish_store}
    >
      <div class="space-y-6">
        <div class="border-b border-base-300 pb-4">
          <h1 class="text-2xl font-bold tracking-tight">Wish Store</h1>
          <p class="text-sm opacity-70">
            Pontos ganhos concluindo atividades, subitens de checklist e prioridades — estornados
            se você desfizer a conclusão depois.
          </p>
        </div>

        <Components.sub_nav active={:wallet} />

        <div class="card qcard border border-base-300 bg-base-100 p-6 text-center">
          <p class="text-xs font-semibold uppercase tracking-wide opacity-60">Saldo atual</p>
          <p class="text-4xl font-bold tracking-tight text-primary">{@balance}</p>
        </div>

        <div class="space-y-2">
          <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Extrato</h2>

          <p
            :if={@entries == []}
            class="rounded-3xl border border-dashed border-base-300 p-10 text-center text-sm opacity-50"
          >
            Nenhum lançamento ainda.
          </p>

          <ul :if={@entries != []} class="space-y-1.5">
            <li
              :for={entry <- @entries}
              class="flex items-center justify-between gap-3 rounded-2xl border border-base-200 px-4 py-2.5"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">{entry.description}</p>
                <p class="text-xs opacity-60">
                  {source_label(entry.source)} · {local_datetime(entry.inserted_at)}
                </p>
              </div>
              <span class={[
                "shrink-0 text-sm font-bold",
                entry.amount >= 0 && "text-success",
                entry.amount < 0 && "text-error"
              ]}>
                {if entry.amount >= 0, do: "+#{entry.amount}", else: entry.amount}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
