defmodule QuizProject.Attempts do
  @moduledoc """
  Domínio de tentativas (implementado na fase de tentativas).
  """

  @doc """
  Associa tentativas anônimas de um token de sessão ao usuário logado.
  """
  def adopt_anonymous_attempts(_user, _participant_token), do: :ok
end
