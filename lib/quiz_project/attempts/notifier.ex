defmodule QuizProject.Attempts.Notifier do
  @moduledoc """
  Notificações PubSub do ciclo de vida das tentativas. É o que permite às
  LiveViews reagirem em tempo real (via socket, sem recarregar a página)
  quando a correção em background termina.

  Tópicos:

    * `attempt:{id}` — quem espera o resultado de uma tentativa específica
      (página de resultado), inclusive participantes anônimos;
    * `user:{id}:attempts` — tudo que acontece com as tentativas de um
      usuário logado (notificação global e painel);
    * `quiz:{id}:attempts` — respostas chegando em um quiz, para o criador
      acompanhar ao vivo na tela de gerenciamento.

  Evento publicado: `{:attempt_finished, %{...}}` com os dados necessários
  para notificar sem nova consulta.
  """

  alias Phoenix.PubSub

  @pubsub QuizProject.PubSub

  def subscribe_attempt(attempt_id), do: PubSub.subscribe(@pubsub, attempt_topic(attempt_id))

  def subscribe_user(user_id), do: PubSub.subscribe(@pubsub, user_topic(user_id))

  def subscribe_quiz(quiz_id), do: PubSub.subscribe(@pubsub, quiz_topic(quiz_id))

  @doc """
  Publica a conclusão da correção de uma tentativa (já carregada com
  `quiz_version`) para a própria tentativa, para o dono da tentativa (se
  logado) e para o quiz (criador acompanhando respostas).
  """
  def broadcast_finished(attempt) do
    payload =
      {:attempt_finished,
       %{
         attempt_id: attempt.id,
         quiz_id: attempt.quiz_version.quiz_id,
         quiz_name: attempt.quiz_version.name,
         version_number: attempt.quiz_version.version_number,
         display_identity: attempt.display_identity,
         score: attempt.score,
         max_score: attempt.max_score,
         percent: attempt.percent
       }}

    PubSub.broadcast(@pubsub, attempt_topic(attempt.id), payload)
    PubSub.broadcast(@pubsub, quiz_topic(attempt.quiz_version.quiz_id), payload)

    if attempt.user_id do
      PubSub.broadcast(@pubsub, user_topic(attempt.user_id), payload)
    end

    :ok
  end

  defp attempt_topic(attempt_id), do: "attempt:#{attempt_id}"
  defp user_topic(user_id), do: "user:#{user_id}:attempts"
  defp quiz_topic(quiz_id), do: "quiz:#{quiz_id}:attempts"
end
