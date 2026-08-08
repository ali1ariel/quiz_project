defmodule QuizProject.AI.Provider do
  @moduledoc """
  Contrato dos providers de IA. A regra de negócio fala apenas com
  `QuizProject.AI`; o provider concreto (OpenAI, Gemini, Claude, Fake) é
  escolhido por configuração.
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
  criador não forneceu resposta de referência.
  """
  @callback generate_reference(statement :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Avalia a evolução do participante respondendo a mesma questão discursiva
  em tentativas sucessivas, a partir de um resumo textual (enunciado e
  respostas em ordem cronológica, com notas e feedback da correção).
  Retorna a análise em texto corrido.
  """
  @callback evaluate_progression(summary :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Decompõe um texto em Mapa Mental Atômico com nós hierárquicos, trechos de texto brutos e referências cruzadas.
  """
  @callback curate_mindmap(text :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
