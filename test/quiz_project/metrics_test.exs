defmodule QuizProject.MetricsTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Metrics
  alias QuizProject.Priorities
  alias QuizProject.Store

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

  defp item(user, category, attrs \\ %{}) do
    {:ok, item} =
      Priorities.create_item(
        user,
        category,
        Map.merge(%{item_type: :manual, title: "Item"}, attrs)
      )

    item
  end

  defp product(user, attrs) do
    {:ok, product} =
      Store.create_product(
        user,
        Map.merge(%{name: "Vale-café", description: "Um café por conta da casa.", price: 100}, attrs)
      )

    product
  end

  describe "priorities_snapshot/1" do
    test "conta categorias e itens ativos/arquivados por tipo e tier, ignorando o item Geral", %{
      user: user
    } do
      category = category(user)
      _general_item_not_counted = category

      ativo = item(user, category, %{item_type: :manual, tier: :S, store_points: 5})
      _outro_ativo = item(user, category, %{item_type: :checklist, store_points: 3})
      arquivado = item(user, category, %{item_type: :manual})
      {:ok, _} = Priorities.archive_item(arquivado, user)

      snapshot = Metrics.priorities_snapshot(user)

      assert snapshot.categories_count == 1
      assert snapshot.items.active_count == 2
      assert snapshot.items.archived_count == 1
      assert snapshot.items.by_type[:manual] == 1
      assert snapshot.items.by_type[:checklist] == 1
      assert snapshot.items.by_tier[:S] == 1
      assert snapshot.items.total_store_points == 8
      assert ativo.tier == :S
    end

    test "conta hábitos ativos/arquivados", %{user: user} do
      category = category(user)
      base_item = item(user, category)

      {:ok, habit} =
        Priorities.create_habit(user, %{item_id: base_item.id, title: "Ler", store_points: 4})

      {:ok, other_habit} =
        Priorities.create_habit(user, %{item_id: base_item.id, title: "Correr", store_points: 6})

      {:ok, _} = Priorities.archive_habit(other_habit, user)

      snapshot = Metrics.priorities_snapshot(user)

      assert snapshot.habits.active_count == 1
      assert snapshot.habits.archived_count == 1
      assert snapshot.habits.avg_store_points == 4.0
      assert habit.store_points == 4
    end
  end

  describe "kanban_snapshot/2" do
    test "distribui atividades por status/flow/kind e calcula taxa de conclusão", %{user: user} do
      {:ok, pendente} = Priorities.create_activity(user, %{title: "Pendente"})
      _pendente = pendente

      {:ok, concluida} = Priorities.create_activity(user, %{title: "Concluída", store_points: 10})
      {:ok, _} = Priorities.complete_activity(concluida, user)

      {:ok, nao_cumprida} = Priorities.create_activity(user, %{title: "Não cumprida"})
      {:ok, _} = Priorities.mark_activity_not_done(nao_cumprida, user)

      snapshot = Metrics.kanban_snapshot(user)

      assert snapshot.total_count == 3
      assert snapshot.by_status[:pendente] == 1
      assert snapshot.by_status[:concluida] == 1
      assert snapshot.by_status[:nao_cumprida] == 1
      assert snapshot.loose_captures_count == 3
      assert snapshot.completion_rate == 0.5
      assert snapshot.recent.count == 3
      assert snapshot.recent.completed_count == 1
      assert snapshot.recent.store_points_earned == 10
    end

    test "completion_rate é nil sem nenhuma atividade resolvida", %{user: user} do
      {:ok, _} = Priorities.create_activity(user, %{title: "Pendente"})

      snapshot = Metrics.kanban_snapshot(user)

      assert snapshot.completion_rate == nil
    end
  end

  describe "store_snapshot/1" do
    test "traz estatística de preço e popularidade dos produtos", %{user: user} do
      barato = product(user, %{name: "Barato", price: 10})
      caro = product(user, %{name: "Caro", price: 90})
      nunca_resgatado = product(user, %{name: "Nunca resgatado", price: 50})

      {:ok, activity} = Priorities.create_activity(user, %{title: "Ganhar", store_points: 200})
      {:ok, _} = Priorities.complete_activity(activity, user)

      {:ok, _} = Store.redeem_product(barato, user)
      {:ok, _} = Store.redeem_product(caro, user)

      snapshot = Metrics.store_snapshot(user)

      assert snapshot.products_count == 3
      assert snapshot.price_stats == %{min: 10, max: 90, avg: 50.0, median: 50}
      assert snapshot.redemptions.count == 2
      assert snapshot.redemptions.total_points_spent == 100
      assert snapshot.products_never_redeemed == [nunca_resgatado.name]

      redeemed_names =
        snapshot.most_redeemed
        |> Enum.filter(&(&1.redemptions > 0))
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert redeemed_names == ["Barato", "Caro"]
    end
  end

  describe "pricing_audit/2" do
    test "cruza preço com ritmo de ganho e saldo atual", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Ganhar", store_points: 30})
      {:ok, _} = Priorities.complete_activity(activity, user)

      barato = product(user, %{name: "Barato", price: 1})
      caro = product(user, %{name: "Caro", price: 300})

      audit = Metrics.pricing_audit(user, window_days: 10)

      assert audit.window_days == 10
      assert audit.avg_daily_earning == 3.0
      assert audit.earning_by_source[:activity] == 30
      assert audit.wallet_balance == 30

      [barato_result, caro_result] = Enum.sort_by(audit.products, & &1.price)
      assert barato_result.id == barato.id
      assert barato_result.days_of_earning == 1 / 3.0
      assert barato_result.affordable_now == true

      assert caro_result.id == caro.id
      assert caro_result.days_of_earning == 100.0
      assert caro_result.affordable_now == false
    end

    test "days_of_earning é nil sem nenhum ganho na janela", %{user: user} do
      product(user, %{price: 10})

      audit = Metrics.pricing_audit(user, window_days: 5)

      assert audit.avg_daily_earning == 0.0
      assert [%{days_of_earning: nil, affordable_now: false}] = audit.products
    end
  end

  describe "overview/2" do
    test "combina as quatro seções", %{user: user} do
      overview = Metrics.overview(user)

      assert Map.has_key?(overview, :priorities)
      assert Map.has_key?(overview, :kanban)
      assert Map.has_key?(overview, :store)
      assert Map.has_key?(overview, :pricing_audit)
    end
  end
end
