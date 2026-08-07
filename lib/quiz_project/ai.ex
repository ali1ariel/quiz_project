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

  @doc """
  Avalia a evolução do participante respondendo a mesma questão discursiva
  em tentativas sucessivas, a partir de um resumo textual do histórico.
  Retorna `{:ok, texto}`.
  """
  def evaluate_progression(summary) when is_binary(summary) do
    provider().evaluate_progression(summary)
  end

  @doc "Decompõe o texto em Mapa Mental Atômico."
  def curate_mindmap(text) when is_binary(text) do
    provider().curate_mindmap(text)
  end

  @doc "Retorna o módulo do provedor de IA atualmente configurado."
  def provider do
    Application.get_env(:quiz_project, :ai_provider, QuizProject.AI.Fake)
  end

  @doc """
  Retorna uma descrição amigável do provedor e modelo de IA em uso. Útil para inspeção no IEx.
  """
  def current_provider do
    case provider() do
      QuizProject.AI.OpenAI ->
        model = Application.get_env(:quiz_project, :openai_model, "gpt-5.5")
        "OpenAI (modelo: #{model})"

      QuizProject.AI.Gemini ->
        model = Application.get_env(:quiz_project, :gemini_model, "gemini-2.0-flash")
        "Gemini (modelo: #{model})"

      QuizProject.AI.Fake ->
        "Fake (heurística local sem IA externa)"

      other ->
        inspect(other)
    end
  end
end
