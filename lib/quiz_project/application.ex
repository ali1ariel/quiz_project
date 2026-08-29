defmodule QuizProject.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_book_images_dir!()

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
        authorization_child() ++
        google_calendar_watch_renewer_child() ++
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

  # As imagens dos livros são o único estado em disco (ver ImageStore). Se o
  # volume persistente não estiver montado em produção, é melhor a aplicação
  # não subir do que subir e falhar só no primeiro upload de um usuário.
  defp ensure_book_images_dir! do
    dir = Application.fetch_env!(:quiz_project, :book_images_dir)

    case File.mkdir_p(dir) do
      :ok ->
        probe = Path.join(dir, ".write_check")

        case File.write(probe, "") do
          :ok ->
            File.rm(probe)

          {:error, reason} ->
            raise "BOOK_IMAGES_DIR (#{dir}) não é gravável: #{:file.format_error(reason)}"
        end

      {:error, reason} ->
        raise "BOOK_IMAGES_DIR (#{dir}) inacessível: #{:file.format_error(reason)}"
    end
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

  # Só sobe o poller quando ele é de fato a implementação escolhida: em teste
  # e em desenvolvimento sem credencial AWS, `:ai_authorization` aponta para
  # `Fake` (lista de configuração, sem rede) — subir o GenServer ali seria
  # trabalho e log de erro sem nenhum uso.
  defp authorization_child do
    if Application.get_env(:quiz_project, :ai_authorization) == QuizProject.AI.Authorization.SSM do
      [QuizProject.AI.Authorization.SSM]
    else
      []
    end
  end

  # Só sobe o renovador quando há um client OAuth do Google configurado e a
  # suíte não desligou explicitamente (mesmo padrão de `enable_chromic_pdf`
  # em config/test.exs) — subir esse GenServer durante os testes faria a
  # primeira consulta ao banco disparar fora do sandbox por-teste do Ecto,
  # já que a Application sobe uma única vez pra suíte inteira.
  defp google_calendar_watch_renewer_child do
    if Application.get_env(:quiz_project, :enable_google_calendar_watch_renewer, true) and
         Application.get_env(:quiz_project, :google_client_id) not in [nil, ""] do
      [QuizProject.GoogleCalendar.WatchRenewer]
    else
      []
    end
  end
end
