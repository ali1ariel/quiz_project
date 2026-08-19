defmodule QuizProject.AI.Authorization.SSM do
  @moduledoc """
  Lista de e-mails autorizados a processar com IA, mantida no AWS SSM
  Parameter Store — fora do banco da aplicação de propósito: quem decide
  quem gasta é operação da conta AWS, não uma tela do produto.

  Busca ao subir e a cada cinco minutos, guardando o resultado numa tabela
  ETS pública: a leitura (`authorized?/1`) nunca faz chamada de rede nem
  passa pelo GenServer.

  Falha de rede, credencial ou parâmetro ausente mantém a última lista boa
  conhecida, só avisando no log — um soluço da AWS não pode desautorizar
  quem já podia processar. Sem nenhuma busca bem-sucedida ainda (primeiro
  boot, ou SSM fora do ar desde sempre), a tabela começa vazia e fecha por
  segurança: ninguém processa até a primeira busca dar certo.
  """
  @behaviour QuizProject.AI.Authorization.Provider

  use GenServer
  require Logger

  @table __MODULE__
  @refresh_interval :timer.minutes(5)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl QuizProject.AI.Authorization.Provider
  def authorized?(email) when is_binary(email) do
    :ets.member(@table, normalize(email))
  rescue
    # Tabela ainda não existe: GenServer não subiu, ou subiu e ainda não
    # rodou o primeiro `init/1`. É o mesmo "ninguém autorizado" de uma busca
    # que já rodou e voltou vazia — não precisa de tratamento à parte.
    ArgumentError -> false
  end

  def authorized?(_), do: false

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    send(self(), :refresh)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    case fetch_emails() do
      {:ok, emails} ->
        replace(emails)

      {:error, reason} ->
        Logger.warning(
          "[AI.Authorization.SSM] Falha ao buscar #{parameter_name()}, mantendo lista anterior: " <>
            inspect(reason)
        )
    end

    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, state}
  end

  defp replace(emails) do
    :ets.delete_all_objects(@table)
    Enum.each(emails, &:ets.insert(@table, {&1}))
  end

  defp fetch_emails do
    with {:ok, %{"Parameter" => %{"Value" => value}}} <- ExAws.request(get_parameter_operation()) do
      emails =
        value
        |> String.split(",")
        |> Enum.map(&normalize/1)
        |> Enum.reject(&(&1 == ""))

      {:ok, emails}
    end
  end

  # `ex_aws_ssm` está sem manutenção desde 2019; a chamada é simples o
  # bastante (uma operação JSON com um único parâmetro) para montar direto
  # sobre `ExAws.Operation.JSON`, sem trazer um pacote parado para o mix.lock.
  defp get_parameter_operation do
    ExAws.Operation.JSON.new(:ssm, %{
      data: %{"Name" => parameter_name(), "WithDecryption" => false},
      headers: [
        {"x-amz-target", "AmazonSSM.GetParameter"},
        {"content-type", "application/x-amz-json-1.1"}
      ]
    })
  end

  defp parameter_name do
    Application.get_env(
      :quiz_project,
      :ai_authorization_parameter,
      "/quiz_project/ai/authorized_emails"
    )
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
