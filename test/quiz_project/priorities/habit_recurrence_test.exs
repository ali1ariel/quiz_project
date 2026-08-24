defmodule QuizProject.Priorities.HabitRecurrenceTest do
  use ExUnit.Case, async: true

  alias QuizProject.Priorities.HabitRecurrence

  describe "due_on?/2" do
    test "diário é sempre devido" do
      config = %{frequency: :daily}
      assert HabitRecurrence.due_on?(config, ~D[2026-08-24])
      assert HabitRecurrence.due_on?(config, ~D[2026-08-30])
    end

    test "semanal só nos dias marcados" do
      # 2026-08-24 é uma segunda-feira (day_of_week == 1)
      config = %{frequency: :weekly, weekdays: [1, 3, 5]}

      assert HabitRecurrence.due_on?(config, ~D[2026-08-24])
      refute HabitRecurrence.due_on?(config, ~D[2026-08-25])
    end

    test "mensal só nos dias marcados" do
      config = %{frequency: :monthly, month_days: [1, 15]}

      assert HabitRecurrence.due_on?(config, ~D[2026-08-01])
      assert HabitRecurrence.due_on?(config, ~D[2026-08-15])
      refute HabitRecurrence.due_on?(config, ~D[2026-08-02])
    end
  end

  describe "streak/4" do
    @daily %{frequency: :daily, weekdays: [], month_days: []}

    test "sequência perfeita conta todos os dias devidos até hoje" do
      today = ~D[2026-08-24]

      statuses = %{
        today => :concluida,
        Date.add(today, -1) => :concluida,
        Date.add(today, -2) => :concluida
      }

      assert HabitRecurrence.streak(@daily, statuses, today) == 3
    end

    test "hoje pendente não quebra, mas também não conta" do
      today = ~D[2026-08-24]
      statuses = %{Date.add(today, -1) => :concluida, Date.add(today, -2) => :concluida}

      assert HabitRecurrence.streak(@daily, statuses, today) == 2
    end

    test "dia devido faltando quebra a sequência" do
      today = ~D[2026-08-24]

      statuses = %{
        today => :concluida,
        # Date.add(today, -1) faltando de propósito
        Date.add(today, -2) => :concluida
      }

      assert HabitRecurrence.streak(@daily, statuses, today) == 1
    end

    test "dia devido marcado não_cumprida quebra a sequência" do
      today = ~D[2026-08-24]
      statuses = %{today => :concluida, Date.add(today, -1) => :nao_cumprida}

      assert HabitRecurrence.streak(@daily, statuses, today) == 1
    end

    test "hábito semanal pula dias não devidos sem quebrar" do
      # 2026-08-24 (segunda) devido; 2026-08-23 (domingo) e 2026-08-22
      # (sábado) não são devidos e não devem quebrar a sequência que
      # continua em 2026-08-21 (sexta).
      config = %{frequency: :weekly, weekdays: [1, 5], month_days: []}
      today = ~D[2026-08-24]

      statuses = %{
        today => :concluida,
        ~D[2026-08-21] => :concluida
      }

      assert HabitRecurrence.streak(config, statuses, today) == 2
    end

    test "sem nenhuma atividade a sequência é zero" do
      assert HabitRecurrence.streak(@daily, %{}, ~D[2026-08-24]) == 0
    end
  end
end
