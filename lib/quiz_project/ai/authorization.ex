defmodule QuizProject.AI.Authorization do
  @moduledoc """
  Fachada de quem pode disparar processamento de IA (custo real por chamada).

  A regra de negócio chama só esta função e nunca a implementação
  diretamente. A fonte concreta é escolhida em tempo de execução via
  `:quiz_project, :ai_authorization`, alimentada no `runtime.exs`:
  `QuizProject.AI.Authorization.SSM` quando há credencial AWS configurada,
  `QuizProject.AI.Authorization.Fake` quando não há (inclusive em teste).

  Falta de configuração fecha por segurança: o padrão é `Fake` com lista
  vazia, então um ambiente sem nenhuma configuração não autoriza ninguém.
  """

  @doc "Se este e-mail pode disparar processamento de IA."
  def authorized?(email) when is_binary(email), do: impl().authorized?(email)
  def authorized?(_), do: false

  defp impl, do: Application.get_env(:quiz_project, :ai_authorization, __MODULE__.Fake)
end
