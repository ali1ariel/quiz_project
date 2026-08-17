defmodule QuizProject.AI.Authorization.Fake do
  @moduledoc """
  Lista fixa de e-mails, vinda de configuração — sem rede, sem GenServer.

  Usada em teste sempre, e fora dele quando não há credencial AWS
  configurada (desenvolvimento local sem acesso à conta): o `runtime.exs`
  já resolve para este módulo nesse caso. Lista vazia por padrão — quem
  desenvolve sem AWS libera o próprio e-mail via `AI_AUTHORIZATION_EMAILS`
  no próprio ambiente, nunca commitado (o repositório é público).
  """
  @behaviour QuizProject.AI.Authorization.Provider

  @impl true
  def authorized?(email) when is_binary(email) do
    normalize(email) in emails()
  end

  def authorized?(_), do: false

  defp emails do
    :quiz_project
    |> Application.get_env(:fake_authorized_emails, [])
    |> Enum.map(&normalize/1)
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
