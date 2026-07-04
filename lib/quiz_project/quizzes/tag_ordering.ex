defmodule QuizProject.Quizzes.TagOrdering do
  @moduledoc """
  Ordenação "aleatória por IA": usa as tags internas geradas na publicação
  para distribuir as questões, evitando que questões semanticamente parecidas
  fiquem em sequência. Nenhuma chamada de IA acontece aqui — apenas as tags
  pré-computadas são usadas.

  Estratégia gulosa: embaralha os candidatos e, a cada passo, escolhe a
  questão com menor sobreposição de tags em relação à anterior.
  """

  def order(questions) when is_list(questions) do
    case Enum.shuffle(questions) do
      [] ->
        []

      [first | rest] ->
        do_order(rest, [first])
        |> Enum.reverse()
    end
  end

  defp do_order([], placed), do: placed

  defp do_order(candidates, [previous | _] = placed) do
    next =
      Enum.min_by(candidates, fn candidate ->
        {overlap(candidate, previous), :rand.uniform()}
      end)

    do_order(List.delete(candidates, next), [next | placed])
  end

  defp overlap(a, b) do
    tags_a = MapSet.new(a.ai_tags || [])
    tags_b = MapSet.new(b.ai_tags || [])

    MapSet.intersection(tags_a, tags_b) |> MapSet.size()
  end
end
