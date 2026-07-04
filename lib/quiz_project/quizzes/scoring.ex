defmodule QuizProject.Quizzes.Scoring do
  @moduledoc """
  Distribuição de pontos entre questões de uma versão.

  Com pesos desiguais desligados, a nota total é dividida igualmente. Com
  pesos ligados, os pesos preenchidos são usados como estão e o restante da
  nota total é distribuído igualmente entre as questões sem peso.
  """

  @doc """
  Retorna um mapa `%{question_id => Decimal.t()}` com os pontos de cada questão.
  """
  def question_points(version, questions) do
    questions = Enum.reject(questions, &is_nil/1)
    count = length(questions)

    cond do
      count == 0 ->
        %{}

      not version.unequal_weights ->
        share = Decimal.div(version.total_points, Decimal.new(count))
        Map.new(questions, &{&1.id, share})

      true ->
        {weighted, unweighted} = Enum.split_with(questions, &(&1.weight != nil))

        used =
          weighted
          |> Enum.map(& &1.weight)
          |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

        remaining = Decimal.max(Decimal.sub(version.total_points, used), Decimal.new(0))

        share =
          case length(unweighted) do
            0 -> Decimal.new(0)
            n -> Decimal.div(remaining, Decimal.new(n))
          end

        Map.new(questions, fn q ->
          {q.id, if(q.weight, do: q.weight, else: share)}
        end)
    end
  end

  @doc "Soma dos pontos possíveis da versão (pontuação máxima real)."
  def max_score(version, questions) do
    version
    |> question_points(questions)
    |> Map.values()
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end
end
