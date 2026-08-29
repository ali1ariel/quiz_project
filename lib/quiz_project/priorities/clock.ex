defmodule QuizProject.Priorities.Clock do
  @moduledoc """
  Fuso horário de Brasília pros resets diários do Kanban (virada de
  `logical_date`/`resolved_date`, fechamento de instância de hábito vencida,
  idade de captura solta). Brasil não observa horário de verão desde 2019,
  então Brasília é sempre UTC-3 fixo — sem precisar de `tzdata`/`Timex` só
  por causa disso.
  """

  def today, do: DateTime.utc_now() |> DateTime.add(-3, :hour) |> DateTime.to_date()
end
