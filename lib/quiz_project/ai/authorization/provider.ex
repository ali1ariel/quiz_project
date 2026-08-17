defmodule QuizProject.AI.Authorization.Provider do
  @moduledoc """
  Contrato de quem decide se um e-mail pode disparar processamento de IA. A
  regra de negócio fala apenas com `QuizProject.AI.Authorization`; a fonte
  concreta (AWS SSM, lista fixa de configuração) é escolhida por configuração,
  no mesmo desenho de `QuizProject.AI.Provider`.
  """

  @doc "Se este e-mail está na lista de autorizados a processar com IA."
  @callback authorized?(email :: String.t()) :: boolean()
end
