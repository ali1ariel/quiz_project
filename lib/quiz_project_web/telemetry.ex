defmodule QuizProjectWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # Rastro de memória/processos no log (journald), a cada 30s, sem
      # depender do LiveDashboard estar aberto — a única forma de ver a
      # tendência de memória subindo antes de uma queda por OOM, já que o
      # kill do kernel não deixa tempo de escrever nada depois do fato.
      # `id` explícito: os dois filhos são o mesmo módulo `:telemetry_poller`,
      # e o supervisor exige ids únicos entre os filhos.
      Supervisor.child_spec(
        {:telemetry_poller, measurements: [{__MODULE__, :log_vm_usage, []}], period: 30_000},
        id: :vm_usage_logger
      )
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def log_vm_usage do
    mem = :erlang.memory()

    Logger.info(
      "[vm] total_mb=#{mb(mem[:total])} processes_mb=#{mb(mem[:processes])} " <>
        "binary_mb=#{mb(mem[:binary])} ets_mb=#{mb(mem[:ets])} " <>
        "process_count=#{:erlang.system_info(:process_count)}"
    )
  end

  defp mb(bytes), do: Float.round(bytes / 1_048_576, 1)

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("quiz_project.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("quiz_project.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("quiz_project.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("quiz_project.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("quiz_project.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {QuizProjectWeb, :count_users, []}
    ]
  end
end
