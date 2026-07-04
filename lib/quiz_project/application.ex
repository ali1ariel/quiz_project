defmodule QuizProject.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuizProjectWeb.Telemetry,
      QuizProject.Repo,
      {DNSCluster, query: Application.get_env(:quiz_project, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: QuizProject.PubSub},
      # Start a worker by calling: QuizProject.Worker.start_link(arg)
      # {QuizProject.Worker, arg},
      # Start to serve requests, typically the last entry
      QuizProjectWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QuizProject.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuizProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
