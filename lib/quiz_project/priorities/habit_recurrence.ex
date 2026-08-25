defmodule QuizProject.Priorities.HabitRecurrence do
  @moduledoc """
  Se um `Habit` é devido numa data — função pura, sem banco, testável
  com um struct literal e uma `Date`. Mesma filosofia que a Fase 5 do
  roadmap pede pra repetição espaçada, aplicada aqui primeiro.
  """

  @doc """
  Se o hábito é devido na data dada. `skipped_dates` é um `MapSet` de datas
  com exceção "pular esse dia" (ver `Priorities.HabitOverride`) — nunca são
  devidas, independente da frequência. `starts_on`/`ends_on` (se presentes
  no hábito — `Map.get/2`, não acesso direto, pra continuar aceitando maps
  literais nos testes) delimitam quando a regra atual vale: usado pra não
  fazer o hábito novo de uma mudança "essa e as próximas" contar como
  devido antes da data da mudança, nem o antigo depois dela.
  """
  def due_on?(habit, date, skipped_dates \\ MapSet.new()) do
    not MapSet.member?(skipped_dates, date) and in_bounds?(habit, date) and
      frequency_due?(habit, date)
  end

  defp in_bounds?(habit, date) do
    starts_on = Map.get(habit, :starts_on)
    ends_on = Map.get(habit, :ends_on)

    (is_nil(starts_on) or Date.compare(date, starts_on) != :lt) and
      (is_nil(ends_on) or Date.compare(date, ends_on) != :gt)
  end

  defp frequency_due?(%{frequency: :daily}, %Date{}), do: true

  defp frequency_due?(%{frequency: :weekly, weekdays: weekdays}, %Date{} = date),
    do: Date.day_of_week(date) in weekdays

  defp frequency_due?(%{frequency: :monthly, month_days: month_days}, %Date{} = date),
    do: date.day in month_days

  @default_lookback_days 3650

  @doc """
  Sequência atual, andando os dias devidos pra trás a partir de `today`.
  `statuses_by_date` é um `%{Date.t() => atom}` (status da `Activity` do
  dia, se houver). Dias não devidos (fora da frequência, fora de
  `starts_on`/`ends_on`, ou em `skipped_dates`) são pulados sem afetar a
  sequência; `today` em si nunca quebra (só conta se já está `:concluida`
  — enquanto pendente, ainda pode ser resolvido no resto do dia). Pura: sem
  banco, sem `Date.utc_today/0` interno — quem chama decide o que é "hoje".
  """
  def streak(
        config,
        statuses_by_date,
        today,
        skipped_dates \\ MapSet.new(),
        lookback_days \\ @default_lookback_days
      ) do
    count_streak(config, statuses_by_date, today, today, 0, lookback_days, skipped_dates)
  end

  defp count_streak(_config, _statuses, _today, _date, acc, 0, _skipped), do: acc

  defp count_streak(config, statuses, today, date, acc, remaining, skipped) do
    cond do
      not due_on?(config, date, skipped) ->
        count_streak(config, statuses, today, Date.add(date, -1), acc, remaining - 1, skipped)

      Map.get(statuses, date) == :concluida ->
        count_streak(
          config,
          statuses,
          today,
          Date.add(date, -1),
          acc + 1,
          remaining - 1,
          skipped
        )

      date == today ->
        count_streak(config, statuses, today, Date.add(date, -1), acc, remaining - 1, skipped)

      true ->
        acc
    end
  end
end
