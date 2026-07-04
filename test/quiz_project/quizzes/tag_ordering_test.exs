defmodule QuizProject.Quizzes.TagOrderingTest do
  use ExUnit.Case, async: true

  alias QuizProject.Quizzes.TagOrdering

  defp question(id, tags), do: %{id: id, ai_tags: tags}

  test "retorna permutação das questões" do
    questions = for i <- 1..10, do: question(i, ["tag#{rem(i, 3)}"])

    ordered = TagOrdering.order(questions)

    assert Enum.sort(Enum.map(ordered, & &1.id)) == Enum.map(1..10, & &1)
  end

  test "intercala grupos de temas iguais quando possível" do
    historia = for i <- 1..3, do: question("h#{i}", ["história"])
    ciencia = for i <- 1..3, do: question("c#{i}", ["ciência"])

    # com dois grupos de mesmo tamanho, o algoritmo guloso sempre alterna
    ordered = TagOrdering.order(historia ++ ciencia)

    adjacent_overlaps =
      ordered
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] ->
        MapSet.intersection(MapSet.new(a.ai_tags), MapSet.new(b.ai_tags)) |> MapSet.size() > 0
      end)

    assert adjacent_overlaps == 0
  end

  test "lida com listas vazias e tags nulas" do
    assert TagOrdering.order([]) == []

    ordered = TagOrdering.order([%{id: 1, ai_tags: nil}, %{id: 2, ai_tags: ["x"]}])
    assert length(ordered) == 2
  end
end
