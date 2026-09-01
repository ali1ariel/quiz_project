defmodule Mix.Tasks.Priorities.DedupeActivities do
  @moduledoc """
  Remove atividades comuns (`kind: :tarefa`) duplicadas — mesmo usuário, item,
  hábito, título e dia (`logical_date`) — mantendo sempre a mais antiga
  (`inserted_at` menor, `id` como desempate) e apagando o resto do grupo.

  Mesmo critério e mesma query do `DELETE` que já roda sozinho dentro da
  migration `add_unique_task_per_day` (antes de criar o índice único) — essa
  task não precisa ser rodada em produção, é só pra inspecionar/limpar o
  banco local antes do deploy, já que `mix` não existe dentro do release.

      mix priorities.dedupe_activities            # dry run, só relata
      mix priorities.dedupe_activities --commit    # apaga de fato

  Sem `--commit`, nada é alterado — só lista os grupos duplicados e quantas
  linhas seriam removidas de cada um.
  """
  use Mix.Task

  alias QuizProject.Repo

  @shortdoc "Relata (ou remove, com --commit) atividades duplicadas antes da migration de unicidade"

  @switches [commit: :boolean]

  @report_query """
  SELECT
    array_agg(id::text ORDER BY inserted_at ASC, id ASC) AS ids,
    user_id::text, item_id::text, habit_id::text, title, logical_date,
    count(*) AS total
  FROM priority_activities
  WHERE kind = 'tarefa'
  GROUP BY user_id, item_id, habit_id, title, logical_date
  HAVING count(*) > 1
  ORDER BY count(*) DESC
  """

  @delete_query """
  DELETE FROM priority_activities pa
  USING (
    SELECT id,
           row_number() OVER (
             PARTITION BY user_id, item_id, habit_id, title, logical_date
             ORDER BY inserted_at ASC, id ASC
           ) AS rn
    FROM priority_activities
    WHERE kind = 'tarefa'
  ) ranked
  WHERE pa.id = ranked.id
    AND ranked.rn > 1
  RETURNING pa.id::text, pa.title, pa.flow, pa.status, pa.logical_date
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest} = OptionParser.parse!(args, switches: @switches)

    %{rows: rows} = Repo.query!(@report_query, [])

    if rows == [] do
      Mix.shell().info("Nenhuma atividade duplicada encontrada.")
    else
      report(rows)

      if opts[:commit] do
        commit()
      else
        Mix.shell().info(
          "\nDry run — nada foi apagado. Rode com --commit pra remover as duplicatas listadas acima."
        )
      end
    end
  end

  defp report(rows) do
    total_extra = Enum.reduce(rows, 0, fn [_ids, _u, _i, _h, _t, _d, total], acc -> acc + total - 1 end)

    Mix.shell().info("#{length(rows)} grupo(s) duplicado(s), #{total_extra} linha(s) a remover:\n")

    Enum.each(rows, fn [ids, _user_id, item_id, habit_id, title, logical_date, total] ->
      [keep | drop] = ids

      Mix.shell().info(
        "- #{inspect(title)} (#{logical_date}, item_id=#{inspect(item_id)}, habit_id=#{inspect(habit_id)}): " <>
          "#{total} cópias — mantém #{keep}, remove #{Enum.join(drop, ", ")}"
      )
    end)
  end

  defp commit do
    %{rows: deleted} = Repo.query!(@delete_query, [])

    Mix.shell().info("\n#{length(deleted)} atividade(s) duplicada(s) removida(s):")

    Enum.each(deleted, fn [id, title, flow, status, logical_date] ->
      Mix.shell().info("  - #{id} #{inspect(title)} flow=#{flow} status=#{status} logical_date=#{logical_date}")
    end)
  end
end
