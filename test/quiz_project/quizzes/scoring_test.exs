defmodule QuizProject.Quizzes.ScoringTest do
  use ExUnit.Case, async: true

  alias QuizProject.Quizzes.Scoring

  defp version(attrs) do
    Map.merge(%{total_points: Decimal.new(100), unequal_weights: false}, attrs)
  end

  defp question(id, weight \\ nil), do: %{id: id, weight: weight}

  test "sem pesos: divide igualmente" do
    points = Scoring.question_points(version(%{}), [question(1), question(2), question(3), question(4)])

    assert Decimal.equal?(points[1], Decimal.new(25))
    assert Enum.all?(Map.values(points), &Decimal.equal?(&1, Decimal.new(25)))
  end

  test "com pesos: usa os definidos e distribui o restante" do
    points =
      Scoring.question_points(
        version(%{unequal_weights: true}),
        [question(1, Decimal.new(40)), question(2), question(3)]
      )

    assert Decimal.equal?(points[1], Decimal.new(40))
    assert Decimal.equal?(points[2], Decimal.new(30))
    assert Decimal.equal?(points[3], Decimal.new(30))
  end

  test "com todos os pesos definidos, máximo é a soma" do
    v = version(%{unequal_weights: true})
    questions = [question(1, Decimal.new(10)), question(2, Decimal.new(20))]

    assert Decimal.equal?(Scoring.max_score(v, questions), Decimal.new(30))
  end

  test "pesos excedendo a nota total não geram restante negativo" do
    points =
      Scoring.question_points(
        version(%{unequal_weights: true}),
        [question(1, Decimal.new(150)), question(2)]
      )

    assert Decimal.equal?(points[1], Decimal.new(150))
    assert Decimal.equal?(points[2], Decimal.new(0))
  end

  test "lista vazia" do
    assert Scoring.question_points(version(%{}), []) == %{}
  end
end
