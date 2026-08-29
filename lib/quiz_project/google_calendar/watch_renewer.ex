defmodule QuizProject.GoogleCalendar.WatchRenewer do
  @moduledoc """
  Renova periodicamente o canal de push notifications (`events.watch`) de
  cada conexão antes que expire. Google não renova sozinho — sem isso o
  sync de entrada simplesmente para de funcionar, silenciosamente, depois
  de alguns dias. Checa a cada 6h e renova quem expira dentro de 24h (ou
  nunca chegou a registrar um canal, ex.: falha na conexão original).

  Mesma estrutura de auto-agendamento de `QuizProject.AI.Authorization.SSM`
  (`Process.send_after` em vez de um scheduler externo).
  """

  use GenServer
  require Logger

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar

  @check_interval :timer.hours(6)
  @renew_within :timer.hours(24)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    send(self(), :renew)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:renew, state) do
    renew_expiring_channels()
    Process.send_after(self(), :renew, @check_interval)
    {:noreply, state}
  end

  defp renew_expiring_channels do
    threshold = DateTime.add(DateTime.utc_now(), @renew_within, :millisecond)

    threshold
    |> Accounts.list_google_calendar_connections_needing_watch_renewal()
    |> Enum.each(&renew_one/1)
  end

  defp renew_one(connection) do
    case GoogleCalendar.renew_watch_channel(connection) do
      {:error, reason} ->
        Logger.warning(
          "[GoogleCalendar.WatchRenewer] Falha ao renovar watch da conexão #{connection.id}: " <>
            inspect(reason)
        )

      _ok ->
        :ok
    end
  end
end
