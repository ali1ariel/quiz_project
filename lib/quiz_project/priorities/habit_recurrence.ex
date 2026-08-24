defmodule QuizProject.Priorities.HabitRecurrence do
  @moduledoc """
  Se um `HabitConfig` é devido numa data — função pura, sem banco, testável
  com um struct literal e uma `Date`. Mesma filosofia que a Fase 5 do
  roadmap pede pra repetição espaçada, aplicada aqui primeiro.
  """

  @doc "Se a configuração de hábito é devida na data dada."
  def due_on?(%{frequency: :daily}, %Date{}), do: true

  def due_on?(%{frequency: :weekly, weekdays: weekdays}, %Date{} = date),
    do: Date.day_of_week(date) in weekdays

  def due_on?(%{frequency: :monthly, month_days: month_days}, %Date{} = date),
    do: date.day in month_days

  @default_lookback_days 3650

  @doc """
  Sequência atual, andando os dias devidos pra trás a partir de `today`.
  `statuses_by_date` é um `%{Date.t() => atom}` (status da `Activity` do
  dia, se houver). Dias não devidos são pulados sem afetar a sequência;
  `today` em si nunca quebra (só conta se já está `:concluida` — enquanto
  pendente, ainda pode ser resolvido no resto do dia). Pura: sem banco, sem
  `Date.utc_today/0` interno — quem chama decide o que é "hoje".
  """
  def streak(config, statuses_by_date, today, lookback_days \\ @default_lookback_days) do
    count_streak(config, statuses_by_date, today, today, 0, lookback_days)
  end

  defp count_streak(_config, _statuses, _today, _date, acc, 0), do: acc

  defp count_streak(config, statuses, today, date, acc, remaining) do
    cond do
      not due_on?(config, date) ->
        count_streak(config, statuses, today, Date.add(date, -1), acc, remaining - 1)

      Map.get(statuses, date) == :concluida ->
        count_streak(config, statuses, today, Date.add(date, -1), acc + 1, remaining - 1)

      date == today ->
        count_streak(config, statuses, today, Date.add(date, -1), acc, remaining - 1)

      true ->
        acc
    end
  end
end
