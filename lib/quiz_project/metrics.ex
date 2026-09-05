defmodule QuizProject.Metrics do
  @moduledoc """
  Leituras agregadas sobre Prioridades, Kanban e Wish Store de um usuário —
  para auditar se os preços da loja fazem sentido perto do que o usuário
  realmente ganha, e como base para um futuro dashboard. Por isso cada
  função devolve números brutos (contagens, distribuições, somas), nunca um
  veredito fechado tipo "caro"/"barato": quem decide isso é quem consome os
  dados, hoje uma auditoria manual, depois talvez uma tela.

  Cruza dados dos domínios `Priorities` e `Store` sem pertencer a nenhum dos
  dois — não é um `Ash.Domain` porque não define recursos próprios, só lê os
  que já existem, sempre com `authorize?: false` e filtro por `user_id`
  fazendo o papel de posse, mesmo padrão usado dentro dos dois domínios.
  """

  require Ash.Query

  alias QuizProject.Priorities
  alias QuizProject.Priorities.{Activity, Category, Clock, Habit, Item, WalletEntry}
  alias QuizProject.Store.{Product, Redemption}

  @default_window_days 30

  @doc """
  Todas as métricas combinadas numa chamada só. `opts` aceita `:window_days`
  (padrão #{@default_window_days}), a janela usada pelo ritmo de ganho de
  pontos em `kanban_snapshot/2` e `pricing_audit/2`.
  """
  def overview(user, opts \\ []) do
    %{
      priorities: priorities_snapshot(user),
      kanban: kanban_snapshot(user, opts),
      store: store_snapshot(user),
      pricing_audit: pricing_audit(user, opts)
    }
  end

  # Prioridades

  @doc "Panorama de categorias, itens e hábitos: contagens por tipo, tier e status de arquivamento."
  def priorities_snapshot(%{id: user_id}) do
    items =
      Item
      |> Ash.Query.filter(user_id == ^user_id and general == false)
      |> Ash.Query.select([:item_type, :tier, :archived_at, :store_points])
      |> Ash.read!(authorize?: false)

    {active_items, archived_items} = Enum.split_with(items, &is_nil(&1.archived_at))

    habits =
      Habit
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:archived_at, :store_points])
      |> Ash.read!(authorize?: false)

    {active_habits, archived_habits} = Enum.split_with(habits, &is_nil(&1.archived_at))

    %{
      categories_count:
        Category |> Ash.Query.filter(user_id == ^user_id) |> Ash.count!(authorize?: false),
      items: %{
        active_count: length(active_items),
        archived_count: length(archived_items),
        by_type: count_by(active_items, & &1.item_type),
        by_tier: count_by(active_items, & &1.tier),
        total_store_points: sum_by(active_items, & &1.store_points)
      },
      habits: %{
        active_count: length(active_habits),
        archived_count: length(archived_habits),
        avg_store_points: avg_by(active_habits, & &1.store_points)
      }
    }
  end

  # Kanban

  @doc """
  Panorama das atividades do Kanban: distribuição por status/flow/tipo, taxa
  de conclusão entre as já resolvidas, e o recorte dos últimos
  `opts[:window_days]` dias (contagem e pontos ganhos).
  """
  def kanban_snapshot(%{id: user_id}, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    since = Date.add(Clock.today(), -window_days)

    activities =
      Activity
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([
        :status,
        :flow,
        :kind,
        :store_points,
        :logical_date,
        :item_id,
        :habit_id
      ])
      |> Ash.read!(authorize?: false)

    resolved = Enum.filter(activities, &(&1.flow == :feito))
    completed = Enum.filter(resolved, &(&1.status == :concluida))
    recent = Enum.filter(activities, &(Date.compare(&1.logical_date, since) != :lt))

    %{
      total_count: length(activities),
      by_status: count_by(activities, & &1.status),
      by_flow: count_by(activities, & &1.flow),
      by_kind: count_by(activities, & &1.kind),
      loose_captures_count: Enum.count(activities, &(is_nil(&1.item_id) and is_nil(&1.habit_id))),
      completion_rate: safe_ratio(length(completed), length(resolved)),
      recent: %{
        window_days: window_days,
        count: length(recent),
        completed_count: Enum.count(recent, &(&1.status == :concluida)),
        store_points_earned:
          recent |> Enum.filter(&(&1.status == :concluida)) |> sum_by(& &1.store_points)
      }
    }
  end

  # Loja

  @doc "Panorama do catálogo e dos resgates: estatística de preço e popularidade de cada produto."
  def store_snapshot(%{id: user_id}) do
    products =
      Product
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:id, :name, :price])
      |> Ash.read!(authorize?: false)

    redemptions =
      Redemption
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:product_id, :price])
      |> Ash.read!(authorize?: false)

    redemptions_by_product = Enum.frequencies_by(redemptions, & &1.product_id)

    %{
      products_count: length(products),
      price_stats: price_stats(Enum.map(products, & &1.price)),
      redemptions: %{
        count: length(redemptions),
        total_points_spent: sum_by(redemptions, & &1.price)
      },
      products_never_redeemed:
        products
        |> Enum.reject(&Map.has_key?(redemptions_by_product, &1.id))
        |> Enum.map(& &1.name),
      most_redeemed:
        products
        |> Enum.map(
          &%{
            id: &1.id,
            name: &1.name,
            price: &1.price,
            redemptions: Map.get(redemptions_by_product, &1.id, 0)
          }
        )
        |> Enum.sort_by(&(-&1.redemptions))
        |> Enum.take(5)
    }
  end

  # Auditoria de preços

  @doc """
  Cruza o preço de cada produto com o ritmo de ganho de pontos do usuário —
  créditos de carteira nos últimos `opts[:window_days]` dias — pra responder
  "esse preço faz sentido?": quantos dias de ganho médio ele custa, e se o
  saldo atual já cobre. `days_of_earning` vem `nil` quando não há ganho
  registrado na janela (divisão por zero evitada de propósito).
  """
  def pricing_audit(%{id: user_id} = user, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    since = DateTime.add(DateTime.utc_now(), -window_days, :day)

    credits =
      WalletEntry
      |> Ash.Query.filter(user_id == ^user_id and amount > 0 and inserted_at >= ^since)
      |> Ash.Query.select([:amount, :source])
      |> Ash.read!(authorize?: false)

    total_credited = sum_by(credits, & &1.amount)
    avg_daily_earning = total_credited / window_days
    balance = Priorities.wallet_balance(user)

    products =
      Product
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:id, :name, :price])
      |> Ash.Query.sort(price: :asc)
      |> Ash.read!(authorize?: false)

    %{
      window_days: window_days,
      avg_daily_earning: avg_daily_earning,
      earning_by_source: sum_grouped_by(credits, & &1.source, & &1.amount),
      wallet_balance: balance,
      products:
        Enum.map(products, fn product ->
          %{
            id: product.id,
            name: product.name,
            price: product.price,
            days_of_earning: safe_div(product.price, avg_daily_earning),
            affordable_now: balance >= product.price
          }
        end)
    }
  end

  # Helpers

  defp count_by(list, fun), do: Enum.frequencies_by(list, fun)

  defp sum_by(list, fun), do: Enum.reduce(list, 0, &(fun.(&1) + &2))

  defp avg_by([], _fun), do: 0.0
  defp avg_by(list, fun), do: sum_by(list, fun) / length(list)

  defp safe_ratio(_num, 0), do: nil
  defp safe_ratio(num, denom), do: num / denom

  defp safe_div(_num, avg) when avg == 0, do: nil
  defp safe_div(num, avg), do: num / avg

  defp sum_grouped_by(list, key_fun, val_fun) do
    list
    |> Enum.group_by(key_fun, val_fun)
    |> Map.new(fn {key, values} -> {key, Enum.sum(values)} end)
  end

  defp price_stats([]), do: %{min: nil, max: nil, avg: nil, median: nil}

  defp price_stats(prices) do
    sorted = Enum.sort(prices)
    count = length(sorted)

    %{
      min: List.first(sorted),
      max: List.last(sorted),
      avg: Enum.sum(sorted) / count,
      median: median(sorted, count)
    }
  end

  defp median(sorted, count) when rem(count, 2) == 1, do: Enum.at(sorted, div(count, 2))

  defp median(sorted, count) do
    (Enum.at(sorted, div(count, 2) - 1) + Enum.at(sorted, div(count, 2))) / 2
  end
end
