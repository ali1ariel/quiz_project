defmodule QuizProject.Priorities.PointDefaultsTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Priorities

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

  describe "get_point_defaults/1" do
    test "zerado quando o usuário ainda não configurou nada", %{user: user} do
      defaults = Priorities.get_point_defaults(user)

      assert defaults.activity_points == 0
      assert defaults.activity_task_points == 0
      assert defaults.item_points == 0
      assert defaults.habit_points == 0
    end
  end

  describe "save_point_defaults/2" do
    test "grava e passa a ser o que get_point_defaults/1 devolve", %{user: user} do
      assert {:ok, _} =
               Priorities.save_point_defaults(user, %{
                 activity_points: 10,
                 activity_task_points: 5,
                 item_points: 20,
                 habit_points: 15
               })

      defaults = Priorities.get_point_defaults(user)
      assert defaults.activity_points == 10
      assert defaults.activity_task_points == 5
      assert defaults.item_points == 20
      assert defaults.habit_points == 15
    end

    test "salvar de novo atualiza a mesma linha (upsert), não duplica", %{user: user} do
      {:ok, _} = Priorities.save_point_defaults(user, %{activity_points: 10})
      {:ok, _} = Priorities.save_point_defaults(user, %{activity_points: 30})

      assert Priorities.get_point_defaults(user).activity_points == 30
    end

    test "é isolado por usuário", %{user: user} do
      {:ok, other} =
        Accounts.register_user(%{email: "outro@teste.com", password: "senha12345"},
          authorize?: false
        )

      {:ok, _} = Priorities.save_point_defaults(user, %{activity_points: 50})

      assert Priorities.get_point_defaults(other).activity_points == 0
    end
  end

  describe "Item.default_activity_store_points" do
    test "começa nil (usa o padrão global) e pode ser sobrescrito", %{user: user} do
      item = manual_item(user, category(user))
      assert item.default_activity_store_points == nil

      {:ok, updated} = Priorities.update_item(item, %{default_activity_store_points: 40}, user)
      assert updated.default_activity_store_points == 40
    end

    test "pode voltar a nil (usar o padrão global de novo)", %{user: user} do
      item = manual_item(user, category(user))
      {:ok, item} = Priorities.update_item(item, %{default_activity_store_points: 40}, user)

      {:ok, item} = Priorities.update_item(item, %{default_activity_store_points: nil}, user)
      assert item.default_activity_store_points == nil
    end
  end
end
