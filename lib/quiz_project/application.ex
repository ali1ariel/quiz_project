defmodule QuizProject.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        QuizProjectWeb.Telemetry,
        QuizProject.Repo,
        {DNSCluster, query: Application.get_env(:quiz_project, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: QuizProject.PubSub},
        # Trabalho em background (correção de tentativas etc.) — ver QuizProject.Jobs
        {Task.Supervisor, name: QuizProject.TaskSupervisor}
      ] ++
        chromic_pdf_child() ++
        [
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

  # Chrome headless para gerar os cards de preview (Open Graph). Desligado em
  # test (não queremos subir Chrome na suíte) — nesse caso a rota de imagem cai
  # no fallback estático. Com `on_demand: true` o Chrome não fica residente
  # ocioso; sobe sob demanda, o que é essencial na instância com pouca RAM.
  defp chromic_pdf_child do
    if Application.get_env(:quiz_project, :enable_chromic_pdf, true) do
      [{ChromicPDF, Application.get_env(:quiz_project, :chromic_pdf, [])}]
    else
      []
    end
  end
end
