defmodule QuizProject.Attempts.Grader do
  @moduledoc """
  Correção de respostas na finalização da tentativa.

  Regras:

    * questão anulada — pontuação integral para qualquer resposta;
    * "não sei" ou sem resposta — zero;
    * verdadeiro/falso e única — tudo ou nada;
    * múltiplas — marcou qualquer incorreta: zero. Só corretas, mas não
      todas: proporcional se a questão permite nota parcial, senão zero.
      Todas as corretas e nenhuma incorreta: nota total;
    * discursiva — IA compara com a referência do criador (resposta de
      referência ou nota do editor). Sem referência, a IA gera a própria e
      isso fica sinalizado. A nota é percent × pontos da questão.

  Se o provider de IA falhar, cai na heurística local (`Fake`) para a
  finalização nunca travar.
  """

  alias QuizProject.AI

  @zero Decimal.new(0)

  @doc """
  Corrige uma resposta. Retorna um mapa com `:score` e, para discursivas,
  `:ai_percent`, `:ai_feedback`, `:ai_reference` e `:ai_reference_generated`.
  """
  def grade(question, answer, points) do
    cond do
      question.annulled -> %{score: points}
      answer.state != :answered or answer.payload in [nil, %{}] -> %{score: @zero}
      true -> grade_by_type(question, answer, points)
    end
  end

  defp grade_by_type(%{type: :true_false} = question, answer, points) do
    if answer.payload["value"] == question.true_false_answer do
      %{score: points}
    else
      %{score: @zero}
    end
  end

  defp grade_by_type(%{type: :single} = question, answer, points) do
    correct = Enum.find(question.options, & &1.correct)

    if correct && answer.payload["option"] == correct.identity_key do
      %{score: points}
    else
      %{score: @zero}
    end
  end

  defp grade_by_type(%{type: :multiple} = question, answer, points) do
    selected = MapSet.new(answer.payload["options"] || [])
    correct = question.options |> Enum.filter(& &1.correct) |> MapSet.new(& &1.identity_key)
    incorrect = question.options |> Enum.reject(& &1.correct) |> MapSet.new(& &1.identity_key)

    marked_incorrect = MapSet.intersection(selected, incorrect) |> MapSet.size()
    marked_correct = MapSet.intersection(selected, correct) |> MapSet.size()
    total_correct = MapSet.size(correct)

    score =
      cond do
        marked_incorrect > 0 ->
          @zero

        marked_correct == 0 ->
          @zero

        marked_correct == total_correct ->
          points

        question.allow_partial_credit ->
          points
          |> Decimal.mult(Decimal.new(marked_correct))
          |> Decimal.div(Decimal.new(total_correct))

        true ->
          @zero
      end

    %{score: score}
  end

  defp grade_by_type(%{type: :text} = question, answer, points) do
    text = String.trim(answer.payload["text"] || "")

    if text == "" do
      %{score: @zero}
    else
      {reference, generated?} = resolve_reference(question)

      %{percent: percent, feedback: feedback} = grade_text(question.statement, reference, text)

      score =
        points
        |> Decimal.mult(Decimal.new(percent))
        |> Decimal.div(Decimal.new(100))

      %{
        score: score,
        ai_percent: percent,
        ai_feedback: feedback,
        ai_reference: reference,
        ai_reference_generated: generated?
      }
    end
  end

  # A referência principal é a resposta de referência do criador; na ausência,
  # a nota do editor. Sem nenhuma das duas, a IA gera uma referência própria.
  defp resolve_reference(question) do
    creator_reference =
      [question.reference_answer, question.editor_note]
      |> Enum.find(fn value -> is_binary(value) and String.trim(value) != "" end)

    case creator_reference do
      nil ->
        case AI.generate_reference(question.statement) do
          {:ok, reference} -> {reference, true}
          {:error, _} -> fallback_reference(question)
        end

      reference ->
        {reference, false}
    end
  end

  defp fallback_reference(question) do
    {:ok, reference} = QuizProject.AI.Fake.generate_reference(question.statement)
    {reference, true}
  end

  defp grade_text(statement, reference, text) do
    case AI.grade_text_answer(statement, reference, text) do
      {:ok, result} ->
        result

      {:error, _} ->
        {:ok, result} = QuizProject.AI.Fake.grade_text_answer(statement, reference, text)
        %{result | feedback: result.feedback <> " (provider de IA indisponível)"}
    end
  end
end
