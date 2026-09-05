defmodule QuizProjectWeb.Api.MetricsController do
  use QuizProjectWeb, :controller

  alias QuizProject.Metrics
  alias QuizProjectWeb.Api.Response

  @doc "Métricas agregadas de Prioridades, Kanban e Wish Store do usuário autenticado."
  def index(conn, _params) do
    Response.ok(conn, Metrics.overview(conn.assigns.current_user))
  end
end
