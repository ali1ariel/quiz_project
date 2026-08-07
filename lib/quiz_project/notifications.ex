defmodule QuizProject.Notifications do
  @moduledoc """
  Notificações persistentes dos eventos em background. A entrega em tempo
  real é do `QuizProject.Attempts.Notifier` (PubSub); aqui fica o registro
  durável, para a notificação sobreviver a navegação e recarga de página até
  o usuário dispensá-la.
  """
  use Ash.Domain, otp_app: :quiz_project

  require Ash.Query

  alias QuizProject.Notifications.Notification

  resources do
    resource Notification
  end

  @doc "Registra a notificação de correção concluída para o dono da tentativa."
  def notify_attempt_finished(attempt) do
    version = attempt.quiz_version

    Notification
    |> Ash.Changeset.for_create(
      :create,
      %{
        user_id: attempt.user_id,
        title: "Correção concluída: \"#{version.name}\"",
        body:
          "Você fez #{format_decimal(attempt.score)}/#{format_decimal(attempt.max_score)} pontos " <>
            "(#{format_decimal(attempt.percent)}%).",
        path: "/attempt/#{attempt.id}/result"
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  @doc "Registra a notificação de Mapa Mental concluído para o usuário."
  def notify_mindmap_generated(material) do
    Notification
    |> Ash.Changeset.for_create(
      :create,
      %{
        user_id: material.user_id,
        title: "Mapa Mental gerado: \"#{material.title}\"",
        body: "O conteúdo foi decomposto em um Mapa Mental atômico. Clique para ver a curadoria.",
        path: "/adaptive-study/#{material.id}/curate"
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  @doc "Registra a notificação de falha no processamento do Mapa Mental."
  def notify_mindmap_failed(material) do
    Notification
    |> Ash.Changeset.for_create(
      :create,
      %{
        user_id: material.user_id,
        title: "Falha ao gerar Mapa Mental",
        body: "Ocorreu um erro no processamento por IA do material \"#{material.title}\".",
        path: "/adaptive-study"
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  @doc "Notificações não lidas do usuário, mais recentes primeiro."
  def list_unread(user_id) do
    Notification
    |> Ash.Query.filter(user_id == ^user_id and is_nil(read_at))
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Marca como lida, garantindo que pertence ao usuário."
  def mark_read(notification_id, user_id) do
    case Ash.get(Notification, notification_id, authorize?: false) do
      {:ok, %Notification{user_id: ^user_id} = notification} ->
        notification
        |> Ash.Changeset.for_update(:mark_read, %{}, authorize?: false)
        |> Ash.update()

      _ ->
        {:error, :not_found}
    end
  end

  defp format_decimal(nil), do: "0"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end
end
