defmodule QuizProject.Release do
  @moduledoc """
  Tarefas executadas dentro do release em produção, sem depender do Mix
  (que não é embarcado no build). Usadas pelos scripts de deploy:

      bin/quiz_project eval "QuizProject.Release.migrate"
  """
  @app :quiz_project

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
