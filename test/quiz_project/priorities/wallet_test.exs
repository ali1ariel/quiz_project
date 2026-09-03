defmodule QuizProject.Priorities.WalletTest do
  use QuizProject.DataCase, async: true

  require Ash.Query

  alias QuizProject.Accounts
  alias QuizProject.Priorities
  alias QuizProject.Priorities.Activity

  setup do
    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user}
  end

  defp category(user, name \\ "Categoria") do
    {:ok, category} = Priorities.create_category(user, %{name: name})
    category
  end

  defp manual_item(user, category, attrs \\ %{}) do
    {:ok, item} =
      Priorities.create_item(
        user,
        category,
        Map.merge(%{item_type: :manual, title: "Item"}, attrs)
      )

    item
  end

  describe "conclusão de atividade" do
    test "credita store_points ao concluir e estorna ao reabrir", %{user: user} do
      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ler capítulo 1", store_points: 10})

      assert Priorities.wallet_balance(user) == 0

      {:ok, activity} = Priorities.complete_activity(activity, user)
      assert Priorities.wallet_balance(user) == 10

      {:ok, _} = Priorities.reopen_activity(activity, user)
      assert Priorities.wallet_balance(user) == 0
    end

    test "não gera lançamento quando store_points é zero", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Sem pontos"})

      {:ok, _} = Priorities.complete_activity(activity, user)

      assert Priorities.wallet_balance(user) == 0
      assert Priorities.list_wallet_entries(user) == []
    end

    test "concluir de novo uma atividade já concluída não credita em dobro", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "X", store_points: 5})

      {:ok, activity} = Priorities.complete_activity(activity, user)
      {:ok, _} = Priorities.complete_activity(activity, user)

      assert Priorities.wallet_balance(user) == 5
    end

    test "mark_activity_not_done e discard_activity estornam se a atividade já estava concluída",
         %{user: user} do
      {:ok, a1} = Priorities.create_activity(user, %{title: "A", store_points: 4})
      {:ok, a1} = Priorities.complete_activity(a1, user)
      {:ok, _} = Priorities.mark_activity_not_done(a1, user)

      {:ok, a2} = Priorities.create_activity(user, %{title: "B", store_points: 6})
      {:ok, a2} = Priorities.complete_activity(a2, user)
      {:ok, _} = Priorities.discard_activity(a2, user)

      assert Priorities.wallet_balance(user) == 0
    end

    test "correct_activity_status credita/estorna conforme o novo desfecho", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "C", store_points: 8})
      {:ok, activity} = Priorities.mark_activity_not_done(activity, user)
      assert Priorities.wallet_balance(user) == 0

      {:ok, activity} = Priorities.correct_activity_status(activity, :concluida, user)
      assert Priorities.wallet_balance(user) == 8

      {:ok, _} = Priorities.correct_activity_status(activity, :nao_cumprida, user)
      assert Priorities.wallet_balance(user) == 0
    end

    test "instância diária de hábito herda store_points do hábito e credita ao concluir", %{
      user: user
    } do
      item = manual_item(user, category(user))
      {:ok, habit} = Priorities.create_habit(user, %{title: "Meditar", item_id: item.id})
      {:ok, habit} = Priorities.set_habit_store_points(habit, 3, user)

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      [activity] =
        Activity
        |> Ash.Query.filter(habit_id == ^habit.id)
        |> Ash.read!(authorize?: false)

      assert activity.store_points == 3

      {:ok, _} = Priorities.complete_activity(activity, user)
      assert Priorities.wallet_balance(user) == 3
    end
  end

  describe "checklist de atividade" do
    test "credita ao marcar subitem como feito e estorna ao desmarcar", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Viagem"})
      {:ok, task} = Priorities.create_activity_task(activity, "Fazer mala", user, 2)

      {:ok, task} = Priorities.toggle_activity_task(task, activity, user)
      assert task.done
      assert Priorities.wallet_balance(user) == 2

      {:ok, _} = Priorities.toggle_activity_task(task, activity, user)
      assert Priorities.wallet_balance(user) == 0
    end
  end

  describe "progresso de prioridade" do
    test "manual: credita ao chegar em 100% e estorna ao sair", %{user: user} do
      item = manual_item(user, category(user), %{store_points: 15})

      {:ok, item} = Priorities.set_manual_percent(item, 50, user)
      assert Priorities.wallet_balance(user) == 0

      {:ok, item} = Priorities.set_manual_percent(item, 100, user)
      assert Priorities.wallet_balance(user) == 15

      {:ok, _} = Priorities.set_manual_percent(item, 80, user)
      assert Priorities.wallet_balance(user) == 0
    end

    test "curso: credita quando concluídas == total", %{user: user} do
      {:ok, item} =
        Priorities.create_item(user, category(user), %{
          item_type: :course,
          title: "Curso",
          store_points: 20,
          course_total_steps: 4
        })

      {:ok, item} =
        Priorities.set_course_progress(item, %{course_completed_steps: 2}, user)

      assert Priorities.wallet_balance(user) == 0

      {:ok, _} =
        Priorities.set_course_progress(item, %{course_completed_steps: 4}, user)

      assert Priorities.wallet_balance(user) == 20
    end

    test "checklist: credita quando todos os subitens são concluídos", %{user: user} do
      {:ok, item} =
        Priorities.create_item(user, category(user), %{
          item_type: :checklist,
          title: "Mudança",
          store_points: 12
        })

      {:ok, t1} = Priorities.create_task(item, "Caixa 1", user)
      {:ok, t2} = Priorities.create_task(item, "Caixa 2", user)

      {:ok, t1} = Priorities.toggle_task(t1, item, user)
      assert Priorities.wallet_balance(user) == 0

      {:ok, _} = Priorities.toggle_task(t2, item, user)
      assert Priorities.wallet_balance(user) == 12

      {:ok, _} = Priorities.toggle_task(t1, item, user)
      assert Priorities.wallet_balance(user) == 0
    end
  end

  describe "wallet_balance/1 e list_wallet_entries/1" do
    test "saldo é a soma dos lançamentos, extrato vem do mais recente pro mais antigo", %{
      user: user
    } do
      {:ok, a1} = Priorities.create_activity(user, %{title: "A", store_points: 5})
      {:ok, a2} = Priorities.create_activity(user, %{title: "B", store_points: 7})

      {:ok, _} = Priorities.complete_activity(a1, user)
      {:ok, _} = Priorities.complete_activity(a2, user)

      assert Priorities.wallet_balance(user) == 12

      entries = Priorities.list_wallet_entries(user)
      assert length(entries) == 2
      assert Enum.map(entries, & &1.amount) == [7, 5]
    end
  end
end
