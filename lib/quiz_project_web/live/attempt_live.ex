defmodule QuizProjectWeb.AttemptLive do
  @moduledoc """
  Fluxo de resposta de uma tentativa: 10 questões por página, estado salvo a
  cada interação, marcar para depois, "não sei", limpar/restaurar com janela
  de 10 segundos e confirmação final com validação de pendências.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Attempts

  @per_page 10
  @restore_seconds 10

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 class="text-xl font-bold">{@version.name}</h1>
          <p class="text-xs opacity-60">Respondendo como "{@attempt.display_identity}"</p>
        </div>
        <span class="badge badge-ghost rounded-full">
          {@answered_count}/{length(@ordered_questions)} respondidas
        </span>
      </div>

      <.pagination
        page={@page}
        page_statuses={@page_statuses}
        id="pagination-top"
      />

      <div class="space-y-4">
        <div
          :for={{question, global_index} <- @page_questions}
          id={"attempt-question-#{question.id}"}
          class={[
            "card qcard p-5",
            question_state_class(answer(@answers, question)) || "bg-base-200"
          ]}
        >
          <div class="flex items-start justify-between gap-2 mb-3">
            <div class="flex items-start gap-3 min-w-0">
              <span class="badge badge-neutral rounded-full mt-0.5">{global_index + 1}</span>
              <p class="qtext font-medium break-words">{question.statement}</p>
            </div>
            <div class="flex flex-col items-end gap-1 shrink-0">
              <span
                :if={answer(@answers, question).imported_from_previous}
                class="badge badge-info badge-sm rounded-full"
                id={"imported-pill-#{question.id}"}
              >
                Importada da versão anterior
              </span>
              <span
                :if={answer(@answers, question).marked_later}
                class="badge badge-warning badge-sm rounded-full"
              >
                responder depois
              </span>
              <span
                :if={answer(@answers, question).state == :dont_know}
                class="badge badge-ghost badge-sm rounded-full"
              >
                não sei
              </span>
            </div>
          </div>

          <.question_inputs question={question} answer={answer(@answers, question)} />

          <div class="flex flex-wrap gap-2 mt-4">
            <button
              phx-click="toggle_later"
              phx-value-question-id={question.id}
              class={[
                "btn btn-sm rounded-full",
                if(answer(@answers, question).marked_later,
                  do: "btn-warning",
                  else: "btn-outline btn-warning"
                )
              ]}
              id={"later-#{question.id}"}
            >
              <.icon name="hero-bookmark" class="size-4" />
              {if answer(@answers, question).marked_later,
                do: "Desmarcar",
                else: "Responder depois"}
            </button>

            <button
              :if={answer(@answers, question).state != :answered}
              phx-click="toggle_dont_know"
              phx-value-question-id={question.id}
              class={[
                "btn btn-sm rounded-full",
                if(answer(@answers, question).state == :dont_know,
                  do: "btn-neutral",
                  else: "btn-outline"
                )
              ]}
              id={"dont-know-#{question.id}"}
            >
              <.icon name="hero-question-mark-circle" class="size-4" />
              {if answer(@answers, question).state == :dont_know,
                do: "Desfazer não sei",
                else: "Não sei a resposta"}
            </button>

            <button
              :if={answer(@answers, question).state == :answered}
              phx-click="clear_answer"
              phx-value-question-id={question.id}
              class="btn btn-sm btn-outline btn-error rounded-full"
              id={"clear-#{question.id}"}
            >
              <.icon name="hero-backspace" class="size-4" /> Limpar respostas
            </button>

            <button
              :if={@restore_timers[answer(@answers, question).id]}
              phx-click="restore_answer"
              phx-value-question-id={question.id}
              class="btn btn-sm btn-info rounded-full"
              id={"restore-#{question.id}"}
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" />
              Restaurar respostas ({@restore_timers[answer(@answers, question).id]}s)
            </button>
          </div>
        </div>
      </div>

      <.pagination
        page={@page}
        page_statuses={@page_statuses}
        id="pagination-bottom"
      />

      <div class="flex justify-end pt-2 pb-10">
        <button
          :if={!@confirm_anyway}
          id="confirm-attempt"
          phx-click="confirm"
          class="btn btn-primary btn-lg rounded-full"
        >
          Confirmar respostas
        </button>
        <button
          :if={@confirm_anyway}
          id="confirm-anyway"
          phx-click="confirm_anyway"
          class="btn btn-warning btn-lg rounded-full"
        >
          Confirmar mesmo assim
        </button>
      </div>

      <dialog :if={@show_confirm_modal} id="confirm-modal" class="modal modal-open">
        <div class="modal-box rounded-2xl">
          <h3 class="font-bold text-lg mb-2">Existem questões pendentes</h3>
          <ul class="text-sm space-y-2 mb-2">
            <li :if={@pending.unanswered > 0} id="pending-unanswered">
              <span class="badge badge-error badge-xs rounded-full mr-1"></span>
              {@pending.unanswered} questão(ões) sem resposta:
              <span class="font-semibold">{format_ranges(@pending_unanswered_numbers)}</span>
            </li>
            <li :if={@pending.later > 0} id="pending-later">
              <span class="badge badge-warning badge-xs rounded-full mr-1"></span>
              {@pending.later} questão(ões) marcada(s) para responder depois:
              <span class="font-semibold">{format_ranges(@pending_later_numbers)}</span>
            </li>
          </ul>
          <p class="text-sm opacity-70">
            Ao confirmar, todas as pendências serão convertidas para "Não sei a
            resposta" (nota zero) e a tentativa será finalizada. Essa ação não
            pode ser desfeita.
          </p>
          <div class="modal-action">
            <button phx-click="cancel_confirm" class="btn btn-ghost rounded-full" id="cancel-confirm">
              Cancelar
            </button>
            <button
              phx-click="finalize_forced"
              class="btn btn-warning rounded-full"
              id="finalize-forced"
            >
              Confirmar e finalizar
            </button>
          </div>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  attr :page, :integer, required: true
  attr :page_statuses, :list, required: true
  attr :id, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <nav :if={length(@page_statuses) > 1} class="flex flex-wrap gap-2 items-center" id={@id}>
      <button
        :for={{status, index} <- Enum.with_index(@page_statuses, 1)}
        phx-click="goto_page"
        phx-value-page={index}
        class={[
          "btn btn-sm btn-circle",
          index == @page && "ring-2 ring-primary ring-offset-2 ring-offset-base-100",
          status_class(status)
        ]}
        id={"#{@id}-page-#{index}"}
        title={"Página #{index}"}
      >
        {index}
      </button>
    </nav>
    """
  end

  defp status_class(:red), do: "btn-error"
  defp status_class(:yellow), do: "btn-warning"
  defp status_class(:green), do: "btn-success"
  defp status_class(:neutral), do: "btn-outline"

  attr :question, :map, required: true
  attr :answer, :map, required: true

  defp question_inputs(%{question: %{type: :true_false}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <button
        :for={{label, value} <- [{"Verdadeiro", true}, {"Falso", false}]}
        phx-click="answer_tf"
        phx-value-question-id={@question.id}
        phx-value-answer={to_string(value)}
        class={[
          "btn rounded-full flex-1 sm:flex-none sm:px-8",
          if(@answer.payload && @answer.payload["value"] == value,
            do: "btn-primary",
            else: "btn-outline"
          )
        ]}
        id={"tf-#{@question.id}-#{value}"}
      >
        {label}
      </button>
    </div>
    """
  end

  defp question_inputs(%{question: %{type: :single}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <button
        :for={option <- @question.options}
        phx-click="answer_single"
        phx-value-question-id={@question.id}
        phx-value-option={option.identity_key}
        class={[
          "btn btn-block justify-start text-left rounded-full font-normal",
          if(@answer.payload && @answer.payload["option"] == option.identity_key,
            do: "btn-primary",
            else: "btn-outline"
          )
        ]}
        id={"single-#{@question.id}-#{option.id}"}
      >
        {option.text}
      </button>
    </div>
    """
  end

  defp question_inputs(%{question: %{type: :multiple}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <button
        :for={option <- @question.options}
        phx-click="toggle_multi"
        phx-value-question-id={@question.id}
        phx-value-option={option.identity_key}
        class={[
          "btn btn-block justify-start text-left rounded-full font-normal",
          if(@answer.payload && option.identity_key in (@answer.payload["options"] || []),
            do: "btn-primary",
            else: "btn-outline"
          )
        ]}
        id={"multi-#{@question.id}-#{option.id}"}
      >
        <.icon
          name={
            if @answer.payload && option.identity_key in (@answer.payload["options"] || []),
              do: "hero-check-circle",
              else: "hero-plus-circle"
          }
          class="size-4"
        /> {option.text}
      </button>
      <p class="text-xs opacity-60">Selecione todas as alternativas corretas.</p>
    </div>
    """
  end

  defp question_inputs(%{question: %{type: :text}} = assigns) do
    ~H"""
    <form phx-change="answer_text" id={"text-form-#{@question.id}"}>
      <input type="hidden" name="question_id" value={@question.id} />
      <textarea
        name="text"
        id={"text-#{@question.id}"}
        rows="4"
        phx-debounce="600"
        class="textarea textarea-bordered w-full rounded-xl"
        placeholder="Escreva sua resposta"
      >{(@answer.payload && @answer.payload["text"]) || ""}</textarea>
    </form>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    attempt = Attempts.get_attempt_full!(id)
    participant = participant(socket)

    with :ok <- Attempts.authorize_participant(attempt, participant) do
      if attempt.status == :finished do
        {:ok, push_navigate(socket, to: ~p"/tentativa/#{attempt.id}/resultado")}
      else
        {:ok,
         socket
         |> assign(attempt: attempt, version: attempt.quiz_version)
         |> assign(page_title: build_title([title_name(attempt.quiz_version.name)]))
         |> assign(page: 1, restore_timers: %{}, confirm_anyway: false, validated: false)
         |> assign(show_confirm_modal: false, pending: %{unanswered: 0, later: 0})
         |> assign(pending_unanswered_numbers: [], pending_later_numbers: [])
         |> rebuild()}
      end
    else
      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Essa tentativa não pertence à sua sessão.")
         |> push_navigate(to: ~p"/")}
    end
  rescue
    Ash.Error.Invalid ->
      {:ok, socket |> put_flash(:error, "Tentativa não encontrada.") |> push_navigate(to: ~p"/")}
  end

  ## Eventos de resposta

  def handle_event("answer_tf", %{"question-id" => question_id, "answer" => value}, socket) do
    save(socket, question_id, %{"value" => value == "true"})
  end

  def handle_event("answer_single", %{"question-id" => question_id, "option" => key}, socket) do
    save(socket, question_id, %{"option" => key})
  end

  def handle_event("toggle_multi", %{"question-id" => question_id, "option" => key}, socket) do
    current = socket.assigns.answers[question_id]
    selected = (current.payload && current.payload["options"]) || []

    new_selection =
      if key in selected, do: List.delete(selected, key), else: selected ++ [key]

    if new_selection == [] do
      clear(socket, question_id)
    else
      save(socket, question_id, %{"options" => new_selection})
    end
  end

  def handle_event("answer_text", %{"question_id" => question_id, "text" => text}, socket) do
    if String.trim(text) == "" do
      answer = socket.assigns.answers[question_id]

      if answer.state == :answered do
        clear(socket, question_id)
      else
        {:noreply, socket}
      end
    else
      save(socket, question_id, %{"text" => text})
    end
  end

  def handle_event("toggle_later", %{"question-id" => question_id}, socket) do
    answer = socket.assigns.answers[question_id]

    case Attempts.toggle_marked_later(socket.assigns.attempt, answer) do
      {:ok, updated} -> {:noreply, put_answer(socket, updated)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("toggle_dont_know", %{"question-id" => question_id}, socket) do
    answer = socket.assigns.answers[question_id]

    case Attempts.toggle_dont_know(socket.assigns.attempt, answer) do
      {:ok, updated} -> {:noreply, put_answer(socket, updated)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("clear_answer", %{"question-id" => question_id}, socket) do
    clear(socket, question_id)
  end

  def handle_event("restore_answer", %{"question-id" => question_id}, socket) do
    answer = socket.assigns.answers[question_id]

    case Attempts.restore_answer(socket.assigns.attempt, answer) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_answer(updated)
         |> update(:restore_timers, &Map.delete(&1, answer.id))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  ## Paginação e confirmação

  def handle_event("goto_page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(page: String.to_integer(page)) |> rebuild()}
  end

  def handle_event("confirm", _params, socket) do
    case Attempts.finalize(socket.assigns.attempt) do
      {:ok, finished} ->
        {:noreply, push_navigate(socket, to: ~p"/tentativa/#{finished.id}/resultado")}

      {:error, {:pending, pending}} ->
        {:noreply,
         socket
         |> assign(confirm_anyway: true, pending: pending, validated: true)
         |> assign_pending_numbers()
         |> rebuild()
         |> put_flash(
           :error,
           "Há questões pendentes. Verifique as páginas em vermelho/amarelo ou confirme mesmo assim."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível finalizar.")}
    end
  end

  def handle_event("confirm_anyway", _params, socket) do
    {:noreply,
     socket
     |> assign(
       show_confirm_modal: true,
       pending: Attempts.pending_summary(socket.assigns.attempt)
     )
     |> assign_pending_numbers()}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, show_confirm_modal: false)}
  end

  def handle_event("finalize_forced", _params, socket) do
    case Attempts.finalize(socket.assigns.attempt, force: true) do
      {:ok, finished} ->
        {:noreply, push_navigate(socket, to: ~p"/tentativa/#{finished.id}/resultado")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível finalizar.")}
    end
  end

  def handle_info({:restore_tick, answer_id}, socket) do
    case socket.assigns.restore_timers[answer_id] do
      nil ->
        {:noreply, socket}

      1 ->
        {:noreply, update(socket, :restore_timers, &Map.delete(&1, answer_id))}

      seconds ->
        Process.send_after(self(), {:restore_tick, answer_id}, 1_000)
        {:noreply, update(socket, :restore_timers, &Map.put(&1, answer_id, seconds - 1))}
    end
  end

  ## Apoio

  defp save(socket, question_id, payload) do
    question = socket.assigns.questions_by_id[question_id]
    answer = socket.assigns.answers[question_id]

    case Attempts.save_answer(socket.assigns.attempt, answer, question, payload) do
      {:ok, updated} ->
        {:noreply, put_answer(socket, updated)}

      {:error, :finished} ->
        {:noreply,
         push_navigate(socket, to: ~p"/tentativa/#{socket.assigns.attempt.id}/resultado")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp clear(socket, question_id) do
    answer = socket.assigns.answers[question_id]

    case Attempts.clear_answer(socket.assigns.attempt, answer) do
      {:ok, updated} ->
        Process.send_after(self(), {:restore_tick, updated.id}, 1_000)

        {:noreply,
         socket
         |> put_answer(updated)
         |> update(:restore_timers, &Map.put(&1, updated.id, @restore_seconds))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp put_answer(socket, answer) do
    socket
    |> update(:answers, &Map.put(&1, answer.question_id, answer))
    |> rebuild()
  end

  defp rebuild(socket) do
    attempt = socket.assigns.attempt
    version = socket.assigns.version

    questions_by_id =
      socket.assigns[:questions_by_id] || Map.new(version.questions, &{&1.id, &1})

    answers =
      socket.assigns[:answers] || Map.new(attempt.answers, &{&1.question_id, &1})

    ordered_questions =
      attempt.question_order
      |> Enum.map(&questions_by_id[&1])
      |> Enum.reject(&is_nil/1)

    pages = Enum.chunk_every(ordered_questions, @per_page)

    page_statuses =
      Enum.map(pages, fn page_questions ->
        page_questions
        |> Enum.map(&answers[&1.id])
        |> Attempts.page_status(socket.assigns[:validated] || false)
      end)

    page = min(max(socket.assigns[:page] || 1, 1), max(length(pages), 1))

    page_questions =
      pages
      |> Enum.at(page - 1, [])
      |> Enum.map(fn question ->
        {question, Enum.find_index(ordered_questions, &(&1.id == question.id))}
      end)

    answered_count = Enum.count(Map.values(answers), &(&1.state != :unanswered))

    assign(socket,
      questions_by_id: questions_by_id,
      answers: answers,
      ordered_questions: ordered_questions,
      page: page,
      page_questions: page_questions,
      page_statuses: page_statuses,
      answered_count: answered_count
    )
  end

  defp answer(answers, question), do: answers[question.id]

  # Feedback visual no card inteiro: âmbar quando marcada para depois,
  # apagado/tracejado quando "não sei". nil = card normal.
  defp question_state_class(answer) do
    cond do
      answer.marked_later -> "qstate-later"
      answer.state == :dont_know -> "qstate-dontknow"
      true -> nil
    end
  end

  # Números (1-based, na ordem da tentativa) das questões pendentes,
  # separados entre sem resposta e marcadas para responder depois.
  defp assign_pending_numbers(socket) do
    numbered =
      socket.assigns.ordered_questions
      |> Enum.with_index(1)
      |> Enum.map(fn {question, number} -> {socket.assigns.answers[question.id], number} end)
      |> Enum.filter(fn {answer, _} -> answer.state == :unanswered end)

    {later, unanswered} = Enum.split_with(numbered, fn {answer, _} -> answer.marked_later end)

    assign(socket,
      pending_unanswered_numbers: Enum.map(unanswered, &elem(&1, 1)),
      pending_later_numbers: Enum.map(later, &elem(&1, 1))
    )
  end

  @doc false
  # Compacta números consecutivos em intervalos: [3, 7, 8, 9, 30..40] →
  # "3, 7 a 9, 30 a 40"
  def format_ranges(numbers) do
    numbers
    |> Enum.sort()
    |> Enum.reduce([], fn number, acc ->
      case acc do
        [{first, last} | rest] when number == last + 1 -> [{first, number} | rest]
        _ -> [{number, number} | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.map_join(", ", fn
      {same, same} -> "#{same}"
      {first, last} -> "#{first} a #{last}"
    end)
  end

  defp participant(socket) do
    %{user: socket.assigns.current_user, token: socket.assigns.participant_token}
  end
end
