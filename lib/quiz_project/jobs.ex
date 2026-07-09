defmodule QuizProject.Jobs do
  @moduledoc """
  Execução de trabalho em background fora do processo que atende o usuário
  (LiveView/controller), para que ele nunca fique bloqueado esperando.

  Em produção roda sob `QuizProject.TaskSupervisor`. Nos testes
  (`:jobs_mode` = `:inline`) roda no próprio processo, para a suíte não
  depender de concorrência nem do sandbox de conexões do Ecto.
  """

  def run(fun) when is_function(fun, 0) do
    case Application.get_env(:quiz_project, :jobs_mode, :async) do
      :inline ->
        fun.()
        :ok

      :async ->
        {:ok, _pid} = Task.Supervisor.start_child(QuizProject.TaskSupervisor, fun)
        :ok
    end
  end
end
