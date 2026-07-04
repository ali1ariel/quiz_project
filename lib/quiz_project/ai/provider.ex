defmodule QuizProject.AI.Provider do
  @moduledoc """
  Contrato dos providers de IA. A regra de negócio fala apenas com
  `QuizProject.AI`; o provider concreto (OpenAI, Gemini, Fake) é escolhido
  por configuração.
  """

  @doc """
  Gera até 4 tags temáticas internas para uma questão a partir do enunciado.
  """
  @callback generate_tags(statement :: String.t()) ::
              {:ok, [String.t()]} | {:error, term()}

  @doc """
  Corrige uma resposta discursiva comparando com a referência.
  Retorna a porcentagem de acerto (0..100) e a explicação da avaliação.
  """
  @callback grade_text_answer(
              statement :: String.t(),
              reference :: String.t(),
              answer :: String.t()
            ) :: {:ok, %{percent: number(), feedback: String.t()}} | {:error, term()}

  @doc """
  Gera uma resposta de referência a partir do enunciado, usada quando o
  criador não forneceu referência nem nota do editor.
  """
  @callback generate_reference(statement :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
