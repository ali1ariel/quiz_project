defmodule QuizProjectWeb.DashboardLive do
  use QuizProjectWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <h1 class="text-2xl font-bold">Meus quizzes</h1>
      <p class="opacity-70">Área do usuário em construção.</p>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
