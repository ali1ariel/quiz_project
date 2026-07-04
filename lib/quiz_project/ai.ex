defmodule QuizProject.AI do
  @moduledoc """
  Fachada da camada de IA. A regra de negócio chama estas funções e nunca um
  provider diretamente. O provider é escolhido em tempo de execução via
  configuração (`:quiz_project, :ai_provider`), alimentada por variáveis de
  ambiente no `runtime.exs`.
  """

  @doc "Gera até 4 tags internas para uma questão. Nunca levanta exceção."
  def generate_tags(statement) when is_binary(statement) do
    case provider().generate_tags(statement) do
      {:ok, tags} when is_list(tags) -> {:ok, Enum.take(tags, 4)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Corrige resposta discursiva contra a referência do criador (ou gerada).
  Retorna `{:ok, %{percent: 0..100, feedback: texto}}`.
  """
  def grade_text_answer(statement, reference, answer) do
    with {:ok, %{percent: percent, feedback: feedback}} <-
           provider().grade_text_answer(statement, reference, answer) do
      {:ok, %{percent: percent |> max(0) |> min(100), feedback: feedback}}
    end
  end

  @doc "Gera resposta de referência quando o criador não forneceu nenhuma."
  def generate_reference(statement) do
    provider().generate_reference(statement)
  end

  def provider do
    Application.get_env(:quiz_project, :ai_provider, QuizProject.AI.Fake)
  end
end
