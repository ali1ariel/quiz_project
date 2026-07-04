defmodule QuizProjectWeb.QuizManageLive do
  @moduledoc """
  Área do criador para um quiz publicado: link público, tentativas recebidas
  (apenas com a identificação escolhida pelo participante), anulação de
  questões da versão publicada e histórico de versões com changelog.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Attempts
  alias QuizProject.Quizzes

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 class="text-2xl font-bold">{@published.name}</h1>
          <p class="text-sm opacity-60">
            Versão publicada<span :if={version_suffix(@published.version_number)}>
              · {version_suffix(@published.version_number)}
            </span>
            — {length(@published.questions)} questões
            <span :if={!@quiz.active} class="text-warning font-medium">· respostas encerradas</span>
          </p>
        </div>
        <div class="flex gap-2">
          <button
            id="toggle-active"
            phx-click="toggle_active"
            data-confirm={
              @quiz.active && "Desativar o quiz? Ninguém poderá enviar novas respostas até reativar."
            }
            class="btn btn-outline rounded-full"
          >
            {if @quiz.active, do: "Desativar quiz", else: "Reativar quiz"}
          </button>
          <button
            id="edit-new-version"
            phx-click="edit_new_version"
            class="btn btn-outline rounded-full"
          >
            <.icon name="hero-pencil" class="size-4" /> Editar (nova versão)
          </button>
          <.link
            :if={@quiz.active}
            href={~p"/q/#{@quiz.public_slug}"}
            target="_blank"
            rel="noopener"
            class="btn btn-primary rounded-full"
          >
            Abrir link público
          </.link>
        </div>
      </div>

      <div class="card qcard bg-base-200 p-4 text-sm flex flex-row items-center gap-2">
        <.icon name="hero-link" class="size-4 opacity-60" />
        <span class="font-mono break-all" id="public-link">{url(~p"/q/#{@quiz.public_slug}")}</span>
      </div>

      <div role="tablist" class="tabs tabs-border">
        <button
          :for={
            {tab, label} <- [
              attempts: "Tentativas",
              questions: "Questões",
              versions: "Histórico de versões"
            ]
          }
          role="tab"
          id={"manage-tab-#{tab}"}
          class={["tab", @tab == tab && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {label}
        </button>
      </div>

      <div :if={@tab == :attempts} id="attempts-panel" class="space-y-3">
        <p :if={@attempts == []} class="opacity-60 text-sm py-8 text-center">
          Nenhuma tentativa finalizada ainda. Compartilhe o link público.
        </p>

        <div
          :for={attempt <- @attempts}
          id={"manage-attempt-#{attempt.id}"}
          class="card qcard bg-base-200 p-4 flex flex-col sm:flex-row sm:items-center gap-3"
        >
          <div class="flex-1">
            <p class="font-semibold">"{attempt.display_identity}"</p>
            <p class="text-xs opacity-60">
              <span :if={version_suffix(attempt.quiz_version.version_number)}>
                {version_suffix(attempt.quiz_version.version_number)} ·
              </span>
              finalizada em {format_datetime(attempt.finished_at)}
            </p>
          </div>
          <span class="badge badge-success rounded-full">
            {format_decimal(attempt.score)}/{format_decimal(attempt.max_score)} pts
            ({format_decimal(attempt.percent)}%)
          </span>
          <.link
            navigate={~p"/tentativa/#{attempt.id}/resultado"}
            class="btn btn-sm btn-outline rounded-full"
            id={"view-attempt-#{attempt.id}"}
          >
            Ver respostas
          </.link>
        </div>
      </div>

      <div :if={@tab == :questions} id="questions-panel" class="space-y-3">
        <p class="text-sm opacity-70">
          Estas são as questões da versão publicada v{@published.version_number}. Alterações
          estruturais exigem uma nova versão; anular uma questão vale para esta versão e concede
          pontuação integral a todos.
        </p>

        <div
          :for={{question, index} <- Enum.with_index(@published.questions)}
          id={"manage-question-#{question.id}"}
          class="card qcard bg-base-200 p-4"
        >
          <div class="flex items-start gap-3">
            <span class="badge badge-neutral rounded-full mt-1">{index + 1}</span>
            <div class="flex-1 min-w-0">
              <p class="qtext font-medium break-words">{question.statement}</p>
              <div class="flex flex-wrap gap-2 mt-1 text-xs">
                <span class="badge badge-ghost badge-sm rounded-full">{type_label(question.type)}</span>
                <span :if={question.annulled} class="badge badge-error badge-sm rounded-full">
                  anulada
                </span>
              </div>
              <p :if={question.annulled && question.annulled_reason} class="text-xs opacity-60 mt-1">
                Motivo da anulação: {question.annulled_reason}
              </p>
            </div>
            <button
              :if={!question.annulled}
              id={"annul-#{question.id}"}
              phx-click="open_annul"
              phx-value-id={question.id}
              class="btn btn-sm btn-ghost text-error rounded-full"
            >
              Anular questão
            </button>
          </div>
        </div>
      </div>

      <div :if={@tab == :versions} id="versions-panel" class="space-y-3">
        <div
          :for={version <- @history}
          id={"version-#{version.id}"}
          class="card qcard bg-base-200 p-4"
        >
          <div class="flex items-center gap-2">
            <span class="badge badge-primary rounded-full">versão {version.version_number}</span>
            <span class="text-sm opacity-60">
              publicada em {format_datetime(version.published_at)}
            </span>
          </div>
          <ul class="mt-2 text-sm list-disc list-inside opacity-80">
            <li :for={entry <- version.changelog}>{entry}</li>
          </ul>
        </div>
      </div>

      <dialog :if={@annul_question} id="annul-modal" class="modal modal-open">
        <div class="modal-box rounded-2xl">
          <h3 class="font-bold text-lg mb-2">Anular questão</h3>
          <p class="text-sm opacity-70 mb-3">
            "{@annul_question.statement}"
          </p>
          <p class="text-sm mb-3">
            A questão permanecerá visível no resultado com selo de anulada e todos os
            participantes recebem a pontuação integral, independentemente da resposta.
            Esta ação é permanente para esta versão.
          </p>
          <form phx-submit="confirm_annul" id="annul-form">
            <textarea
              name="reason"
              id="annul-reason"
              rows="3"
              required
              class="textarea textarea-bordered w-full rounded-xl"
              placeholder="Explique o motivo da anulação (será exibido aos participantes)"
            ></textarea>
            <div class="modal-action">
              <button type="button" phx-click="close_annul" class="btn btn-ghost rounded-full">
                Cancelar
              </button>
              <button type="submit" id="confirm-annul" class="btn btn-error rounded-full">
                Anular questão
              </button>
            </div>
          </form>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  def mount(%{"quiz_id" => quiz_id}, _session, socket) do
    quiz = Quizzes.get_quiz!(quiz_id)

    with :ok <- Quizzes.authorize_owner(quiz, socket.assigns.current_user),
         published when not is_nil(published) <- Quizzes.latest_published_version(quiz) do
      {:ok,
       socket
       |> assign(quiz: quiz, tab: :attempts, annul_question: nil)
       |> assign(page_title: build_title(["Gerenciando", title_name(published.name)]))
       |> load_published(published.id)
       |> load_attempts()
       |> assign(history: Quizzes.version_history(quiz))}
    else
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Este quiz ainda não tem versão publicada.")
         |> push_navigate(to: ~p"/painel")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Você não tem acesso a esse quiz.")
         |> push_navigate(to: ~p"/painel")}
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: String.to_existing_atom(tab))}
  end

  def handle_event("toggle_active", _params, socket) do
    quiz = socket.assigns.quiz

    case Quizzes.set_quiz_active(quiz, !quiz.active, socket.assigns.current_user) do
      {:ok, updated} ->
        message =
          if quiz.active,
            do: "Quiz desativado. Novas respostas estão bloqueadas.",
            else: "Quiz reativado. Já aceita respostas."

        {:noreply, socket |> assign(quiz: updated) |> put_flash(:info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível alterar o status do quiz.")}
    end
  end

  def handle_event("edit_new_version", _params, socket) do
    case Quizzes.ensure_draft(socket.assigns.quiz, socket.assigns.current_user) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: ~p"/quiz/#{draft.id}/editar")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível criar o rascunho.")}
    end
  end

  def handle_event("open_annul", %{"id" => id}, socket) do
    question = Enum.find(socket.assigns.published.questions, &(&1.id == id))
    {:noreply, assign(socket, annul_question: question)}
  end

  def handle_event("close_annul", _params, socket) do
    {:noreply, assign(socket, annul_question: nil)}
  end

  def handle_event("confirm_annul", %{"reason" => reason}, socket) do
    case Quizzes.annul_question(
           socket.assigns.annul_question,
           reason,
           socket.assigns.current_user
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(annul_question: nil)
         |> load_published(socket.assigns.published.id)
         |> load_attempts()
         |> assign(history: Quizzes.version_history(socket.assigns.quiz))
         |> put_flash(:info, "Questão anulada. Todos recebem a pontuação integral.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível anular a questão.")}
    end
  end

  defp load_published(socket, version_id) do
    version = Quizzes.get_version_full!(version_id)

    assign(socket,
      published: %{version | questions: Enum.sort_by(version.questions, & &1.position)}
    )
  end

  defp load_attempts(socket) do
    {:ok, attempts} =
      Attempts.list_attempts_for_quiz(socket.assigns.quiz, socket.assigns.current_user)

    assign(socket, attempts: attempts)
  end

  defp type_label(:true_false), do: "Verdadeiro ou falso"
  defp type_label(:single), do: "Uma correta"
  defp type_label(:multiple), do: "Múltiplas corretas"
  defp type_label(:text), do: "Discursiva"

  defp format_decimal(nil), do: "0"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end
end
