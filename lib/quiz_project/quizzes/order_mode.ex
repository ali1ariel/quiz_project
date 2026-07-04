defmodule QuizProject.Quizzes.OrderMode do
  @moduledoc """
  Modos de ordenação das questões: ordem definida, aleatória ou aleatória por IA.

  O modo `:ai` não chama IA no momento da resposta: usa as tags internas
  geradas na publicação para intercalar questões de temas diferentes.
  """
  use Ash.Type.Enum, values: [:fixed, :random, :ai]
end
