defmodule QuizProject.AI.Fake do
  @moduledoc """
  Provider determinístico para desenvolvimento e testes, sem chamadas HTTP.

  Tags: palavras mais relevantes do enunciado. Correção discursiva:
  similaridade de vocabulário (Jaccard) entre resposta e referência.
  """
  @behaviour QuizProject.AI.Provider

  @stopwords ~w(
    a o as os um uma uns umas de do da dos das em no na nos nas por para com
    sem sob sobre e ou que se ao aos à às é são foi ser estar como qual quais
    quando onde quem cujo cuja isso isto aquilo ele ela eles elas seu sua seus
    suas nem mais menos muito pouco também já não sim entre até desde
  )

  @impl true
  def generate_tags(statement) do
    tags =
      statement
      |> tokenize()
      |> Enum.frequencies()
      |> Enum.sort_by(fn {word, freq} -> {-freq, -String.length(word), word} end)
      |> Enum.take(4)
      |> Enum.map(fn {word, _} -> word end)

    {:ok, tags}
  end

  @impl true
  def grade_text_answer(_statement, reference, answer) do
    reference_tokens = MapSet.new(tokenize(reference))
    answer_tokens = MapSet.new(tokenize(answer))

    percent =
      cond do
        MapSet.size(answer_tokens) == 0 ->
          0

        MapSet.size(reference_tokens) == 0 ->
          0

        true ->
          intersection = MapSet.intersection(reference_tokens, answer_tokens) |> MapSet.size()
          union = MapSet.union(reference_tokens, answer_tokens) |> MapSet.size()
          round(intersection / union * 100)
      end

    feedback =
      cond do
        percent >= 80 ->
          "A resposta cobre os principais pontos da referência."

        percent >= 40 ->
          "A resposta aborda parte dos pontos esperados, mas deixa lacunas em relação à referência."

        true ->
          "A resposta diverge substancialmente da referência esperada."
      end

    {:ok,
     %{percent: percent, feedback: feedback <> " (avaliação heurística local, sem IA externa)"}}
  end

  @impl true
  def generate_reference(statement) do
    {:ok,
     "Resposta de referência gerada automaticamente a partir do enunciado: " <>
       "espera-se que o participante aborde diretamente o que é pedido em \"#{String.slice(statement, 0, 160)}\"."}
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split()
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 3))
  end
end
