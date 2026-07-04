defmodule QuizProjectWeb.Api.Serializer do
  @moduledoc false

  def quiz(quiz) do
    %{
      id: quiz.id,
      public_slug: quiz.public_slug,
      active: quiz.active,
      inserted_at: datetime(quiz.inserted_at),
      updated_at: datetime(quiz.updated_at),
      versions: Enum.map(quiz.versions, &version_summary/1)
    }
  end

  def version(version) do
    %{
      id: version.id,
      quiz_id: version.quiz_id,
      version_number: version.version_number,
      name: version.name,
      description: version.description,
      total_points: decimal(version.total_points),
      unequal_weights: version.unequal_weights,
      question_order_mode: to_string(version.question_order_mode),
      status: to_string(version.status),
      published_at: datetime(version.published_at),
      changelog: version.changelog,
      inserted_at: datetime(version.inserted_at),
      updated_at: datetime(version.updated_at),
      questions: Enum.map(version.questions, &question/1)
    }
  end

  def question(question) do
    %{
      id: question.id,
      identity_key: question.identity_key,
      position: question.position,
      statement: question.statement,
      type: to_string(question.type),
      allow_partial_credit: question.allow_partial_credit,
      true_false_answer: question.true_false_answer,
      editor_note: question.editor_note,
      weight: decimal(question.weight),
      annulled: question.annulled,
      annulled_reason: question.annulled_reason,
      options: Enum.map(question.options, &option/1)
    }
  end

  def option(option) do
    %{
      id: option.id,
      identity_key: option.identity_key,
      position: option.position,
      text: option.text,
      correct: option.correct
    }
  end

  def option_attrs(option) do
    %{id: option.id, position: option.position, text: option.text, correct: option.correct}
  end

  defp version_summary(version) do
    %{
      id: version.id,
      version_number: version.version_number,
      name: version.name,
      status: to_string(version.status),
      published_at: datetime(version.published_at),
      updated_at: datetime(version.updated_at)
    }
  end

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
