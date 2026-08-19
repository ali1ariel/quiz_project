defmodule QuizProject.Priorities.Changes.CheckInHabit do
  @moduledoc """
  Streak diário de hábito: marcar de novo no mesmo dia não muda nada; marcar no
  dia seguinte ao último check-in incrementa a sequência; qualquer intervalo
  maior (ou primeira marcação) reseta a sequência para 1.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    item = changeset.data
    today = Date.utc_today()

    case item.habit_last_checked_on do
      ^today ->
        changeset

      nil ->
        set_streak(changeset, 1, today)

      last_checked_on ->
        if Date.diff(today, last_checked_on) == 1 do
          set_streak(changeset, item.habit_current_streak + 1, today)
        else
          set_streak(changeset, 1, today)
        end
    end
  end

  defp set_streak(changeset, streak, today) do
    changeset
    |> Ash.Changeset.force_change_attribute(:habit_current_streak, streak)
    |> Ash.Changeset.force_change_attribute(:habit_last_checked_on, today)
  end
end
