defmodule QuizProject.Quizzes.QuestionType do
  @moduledoc """
  Tipos de pergunta: verdadeiro/falso, uma correta, múltiplas corretas e discursiva.
  """
  use Ash.Type.Enum, values: [:true_false, :single, :multiple, :text]
end
