defmodule QuizProjectWeb.ResultLive do
  @moduledoc """
  Resultado e correção de uma tentativa finalizada. A mesma tela serve o
  participante e o criador do quiz (somente leitura) — o criador vê apenas a
  identificação escolhida pelo participante.

  Na web o resumo aparece na lateral; no mobile, numa gaveta na parte de
  baixo com toggle.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Attempts
  alias QuizProject.Quizzes
  alias QuizProject.Quizzes.Scoring

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div
        :if={@role == :creator}
        class="alert alert-info rounded-2xl text-sm"
        id="creator-banner"
      >
        <.icon name="hero-eye" class="size-5" />
        Você está vendo a tentativa de "{@attempt.display_identity}" (somente leitura).
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 class="text-2xl font-bold">{@version.name}</h1>
          <p class="text-sm opacity-60">
            Resultado de "{@attempt.display_identity}" — versão v{@version.version_number}
          </p>
        </div>
        <div class="text-right">
          <p class="text-3xl font-bold text-primary" id="final-score">
            {format_decimal(@attempt.score)}<span class="text-lg opacity-60">/{format_decimal(
              @attempt.max_score
            )}</span>
          </p>
          <p class="text-sm opacity-60">{format_decimal(@attempt.percent)}% de aproveitamento</p>
        </div>
      </div>

      <div class="grid lg:grid-cols-[1fr_280px] gap-6 items-start pb-24 lg:pb-4">
        <div class="space-y-4 min-w-0">
          <div
            :for={{question, index} <- Enum.with_index(@ordered_questions)}
            id={"result-question-#{question.id}"}
            class="card bg-base-200 rounded-2xl p-5"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex items-start gap-3 min-w-0">
                <span class="badge badge-neutral rounded-full mt-0.5">{index + 1}</span>
                <p class="font-medium break-words">{question.statement}</p>
              </div>
              <.status_badge
                question={question}
                answer={answer(@answers, question)}
                points={@points[question.id]}
              />
            </div>

            <div
              :if={question.annulled}
              class="alert alert-warning rounded-xl mt-3 text-sm"
              id={"annulled-#{question.id}"}
            >
              <.icon name="hero-shield-exclamation" class="size-5" />
              <div>
                <p class="font-semibold">Questão anulada — pontuação integral concedida a todos</p>
                <p :if={question.annulled_reason} class="opacity-80">
                  Motivo: {question.annulled_reason}
                </p>
              </div>
            </div>

            <div class="mt-4 space-y-3 text-sm">
              <div>
                <p class="text-xs uppercase opacity-50 mb-1">Sua resposta</p>
                <.user_answer question={question} answer={answer(@answers, question)} />
              </div>

              <div :if={question.type != :text}>
                <p class="text-xs uppercase opacity-50 mb-1">Resposta correta</p>
                <.correct_answer question={question} />
              </div>

              <div class="flex items-center gap-2">
                <p class="text-xs uppercase opacity-50">Nota obtida:</p>
                <span class="font-semibold">
                  {format_decimal(answer(@answers, question).score)} de {format_decimal(
                    @points[question.id]
                  )}
                </span>
                <span
                  :if={question.type == :text && answer(@answers, question).ai_percent}
                  class="badge badge-ghost badge-sm rounded-full"
                >
                  IA: {answer(@answers, question).ai_percent}% de acerto
                </span>
              </div>

              <div :if={question.editor_note} class="bg-base-100 rounded-xl p-3">
                <p class="text-xs uppercase opacity-50 mb-1">Resposta de referência</p>
                <p class="whitespace-pre-wrap">{question.editor_note}</p>
              </div>

              <div
                :if={question.type == :text && answer(@answers, question).ai_feedback}
                class="bg-base-100 rounded-xl p-3 border-l-4 border-primary"
                id={"ai-feedback-#{question.id}"}
              >
                <p class="text-xs uppercase opacity-50 mb-1">Nota da Inteligência Artificial</p>
                <p class="whitespace-pre-wrap">{answer(@answers, question).ai_feedback}</p>

                <div
                  :if={answer(@answers, question).ai_reference_generated}
                  class="mt-2 pt-2 border-t border-base-300"
                >
                  <p class="text-xs opacity-60 mb-1">
                    <.icon name="hero-sparkles" class="size-3 inline" />
                    O criador não forneceu resposta de referência — a referência abaixo foi
                    gerada pela IA a partir do enunciado:
                  </p>
                  <p class="text-xs opacity-80 whitespace-pre-wrap">
                    {answer(@answers, question).ai_reference}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- resumo lateral (desktop) --%>
        <aside class="hidden lg:block sticky top-4" id="summary-desktop">
          <.summary attempt={@attempt} stats={@stats} />
        </aside>
      </div>

      <%!-- resumo em gaveta (mobile) --%>
      <div class="lg:hidden fixed bottom-0 inset-x-0 z-20" id="summary-mobile">
        <div class="bg-base-200 border-t border-base-300 rounded-t-2xl shadow-lg">
          <button
            phx-click="toggle_summary"
            class="w-full flex items-center justify-between px-5 py-3"
            id="toggle-summary"
          >
            <span class="font-semibold text-sm">
              Resumo — {format_decimal(@attempt.score)}/{format_decimal(@attempt.max_score)} pts
            </span>
            <.icon
              name={if @show_summary, do: "hero-chevron-down", else: "hero-chevron-up"}
              class="size-5"
            />
          </button>
          <div :if={@show_summary} class="px-5 pb-5">
            <.summary attempt={@attempt} stats={@stats} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :attempt, :map, required: true
  attr :stats, :map, required: true

  defp summary(assigns) do
    ~H"""
    <div class="card bg-base-200 lg:bg-base-200 rounded-2xl lg:p-5 space-y-3">
      <h2 class="font-semibold hidden lg:block">Resumo do quiz</h2>
      <ul class="text-sm space-y-2">
        <li class="flex justify-between">
          <span class="opacity-70">Nota total</span>
          <span class="font-semibold">
            {format_decimal(@attempt.score)}/{format_decimal(@attempt.max_score)}
          </span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">Percentual</span>
          <span class="font-semibold">{format_decimal(@attempt.percent)}%</span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">Respondidas</span>
          <span class="font-semibold">{@stats.answered}/{@stats.total}</span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">"Não sei"</span>
          <span class="font-semibold">{@stats.dont_know}</span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">Questões anuladas</span>
          <span class="font-semibold">{@stats.annulled}</span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">Discursivas avaliadas por IA</span>
          <span class="font-semibold">{@stats.ai_graded}</span>
        </li>
        <li class="flex justify-between">
          <span class="opacity-70">Respostas importadas</span>
          <span class="font-semibold">{@stats.imported}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :answer, :map, required: true
  attr :points, :map, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm rounded-full shrink-0", badge_class(@question, @answer, @points)]}>
      {badge_label(@question, @answer, @points)}
    </span>
    """
  end

  defp badge_class(question, answer, points) do
    cond do
      question.annulled -> "badge-warning"
      answer.state == :dont_know -> "badge-ghost"
      zero?(answer.score) -> "badge-error"
      full?(answer.score, points) -> "badge-success"
      true -> "badge-warning"
    end
  end

  defp badge_label(question, answer, points) do
    cond do
      question.annulled -> "anulada"
      answer.state == :dont_know -> "não sei"
      zero?(answer.score) -> "incorreta"
      full?(answer.score, points) -> "correta"
      true -> "parcialmente correta"
    end
  end

  defp zero?(nil), do: true
  defp zero?(score), do: Decimal.compare(score, Decimal.new(0)) != :gt

  defp full?(nil, _points), do: false
  defp full?(score, points), do: Decimal.compare(score, points) != :lt

  attr :question, :map, required: true
  attr :answer, :map, required: true

  defp user_answer(assigns) do
    ~H"""
    <div>
      <%= cond do %>
        <% @answer.state == :dont_know -> %>
          <p class="italic opacity-60">Não sei a resposta</p>
        <% @answer.payload in [nil, %{}] -> %>
          <p class="italic opacity-60">Sem resposta</p>
        <% @question.type == :true_false -> %>
          <p>{if @answer.payload["value"], do: "Verdadeiro", else: "Falso"}</p>
        <% @question.type == :single -> %>
          <p>{option_text(@question, @answer.payload["option"])}</p>
        <% @question.type == :multiple -> %>
          <ul class="list-disc list-inside">
            <li :for={key <- @answer.payload["options"] || []}>{option_text(@question, key)}</li>
          </ul>
        <% @question.type == :text -> %>
          <p class="whitespace-pre-wrap">{@answer.payload["text"]}</p>
      <% end %>
      <span
        :if={@answer.imported_from_previous}
        class="badge badge-info badge-xs rounded-full mt-1"
      >
        Importada da versão anterior
      </span>
    </div>
    """
  end

  attr :question, :map, required: true

  defp correct_answer(assigns) do
    ~H"""
    <div>
      <%= case @question.type do %>
        <% :true_false -> %>
          <p>{if @question.true_false_answer, do: "Verdadeiro", else: "Falso"}</p>
        <% :single -> %>
          <p>{@question.options |> Enum.find(& &1.correct) |> then(&(&1 && &1.text))}</p>
        <% :multiple -> %>
          <ul class="list-disc list-inside">
            <li :for={option <- Enum.filter(@question.options, & &1.correct)}>{option.text}</li>
          </ul>
        <% :text -> %>
          <p class="opacity-60 italic">Correção por IA com base na referência</p>
      <% end %>
    </div>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    attempt = Attempts.get_attempt_full!(id)
    version = attempt.quiz_version

    role = viewer_role(attempt, version, socket)

    cond do
      role == nil ->
        {:ok,
         socket
         |> put_flash(:error, "Você não tem acesso a essa tentativa.")
         |> push_navigate(to: ~p"/")}

      attempt.status != :finished and role == :participant ->
        {:ok, push_navigate(socket, to: ~p"/tentativa/#{attempt.id}")}

      attempt.status != :finished ->
        {:ok,
         socket
         |> put_flash(:error, "Essa tentativa ainda está em andamento.")
         |> push_navigate(to: ~p"/quiz/#{version.quiz_id}/gerenciar")}

      true ->
        questions_by_id = Map.new(version.questions, &{&1.id, &1})
        answers = Map.new(attempt.answers, &{&1.question_id, &1})

        ordered_questions =
          attempt.question_order
          |> Enum.map(&questions_by_id[&1])
          |> Enum.reject(&is_nil/1)

        {:ok,
         assign(socket,
           attempt: attempt,
           version: version,
           role: role,
           answers: answers,
           ordered_questions: ordered_questions,
           points: Scoring.question_points(version, version.questions),
           stats: stats(version, attempt, answers),
           show_summary: false
         )}
    end
  end

  def handle_event("toggle_summary", _params, socket) do
    {:noreply, update(socket, :show_summary, &(!&1))}
  end

  defp viewer_role(attempt, version, socket) do
    participant = %{
      user: socket.assigns.current_user,
      token: socket.assigns.participant_token
    }

    cond do
      Attempts.authorize_participant(attempt, participant) == :ok ->
        :participant

      match?(:ok, owner_check(version, socket.assigns.current_user)) ->
        :creator

      true ->
        nil
    end
  end

  defp owner_check(version, user) do
    Quizzes.authorize_owner(Quizzes.get_quiz!(version.quiz_id), user)
  end

  defp stats(version, _attempt, answers) do
    values = Map.values(answers)
    questions_by_id = Map.new(version.questions, &{&1.id, &1})

    %{
      total: map_size(answers),
      answered: Enum.count(values, &(&1.state == :answered)),
      dont_know: Enum.count(values, &(&1.state == :dont_know)),
      annulled: Enum.count(version.questions, & &1.annulled),
      imported: Enum.count(values, & &1.imported_from_previous),
      ai_graded:
        Enum.count(values, fn answer ->
          question = questions_by_id[answer.question_id]
          question && question.type == :text && answer.ai_percent != nil
        end)
    }
  end

  defp answer(answers, question), do: answers[question.id]

  defp option_text(question, identity_key) do
    case Enum.find(question.options, &(&1.identity_key == identity_key)) do
      nil -> "(alternativa removida)"
      option -> option.text
    end
  end

  defp format_decimal(nil), do: "0"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end
end
