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
        <div class="text-right hidden md:block">
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
          <.pagination page={@page} page_count={@page_count} id="result-pagination-top" />

          <div
            :for={{question, index} <- @page_questions}
            id={"result-question-#{question.id}"}
            class={[
              "card qcard p-5",
              result_state_class(question, answer(@answers, question), @points[question.id])
            ]}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex items-start gap-3 min-w-0">
                <span class="badge badge-neutral rounded-full mt-0.5">{index + 1}</span>
                <p class="qtext font-medium break-words">{question.statement}</p>
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
                <p class="text-xs uppercase opacity-50 mb-1">
                  {if @role == :creator, do: "Resposta do participante", else: "Sua resposta"}
                </p>
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

          <.pagination page={@page} page_count={@page_count} id="result-pagination-bottom" />
        </div>

        <%!-- resumo lateral (desktop) --%>
        <aside class="hidden lg:block sticky top-4" id="summary-desktop">
          <div class="card qcard bg-base-200 p-5 space-y-3">
            <h2 class="font-semibold text-base">Resumo do quiz</h2>
            <.summary attempt={@attempt} stats={@stats} />
          </div>
        </aside>
      </div>

      <%!-- cortina de resumo (mobile): sobe do rodapé por cima das questões --%>
      <div class="lg:hidden fixed bottom-0 inset-x-0 z-30" id="summary-mobile">
        <div class="bg-base-200 border-t-2 border-base-300 rounded-t-2xl shadow-[0_-10px_32px_rgba(0,0,0,0.28)]">
          <button
            phx-click="toggle_summary"
            class="w-full px-5 pt-2.5 pb-3 cursor-pointer"
            id="toggle-summary"
            aria-expanded={to_string(@show_summary)}
            aria-controls="summary-sheet-body"
          >
            <span class="block mx-auto w-10 h-1 rounded-full bg-base-content/25 mb-2.5"></span>
            <span class="flex items-center justify-between gap-3">
              <span class="font-semibold text-sm text-left">
                Resumo — {format_decimal(@attempt.score)}/{format_decimal(@attempt.max_score)} pts
                · {format_decimal(@attempt.percent)}%
              </span>
              <span class="flex items-center gap-1 text-xs opacity-60 shrink-0">
                {if @show_summary, do: "fechar", else: "expandir"}
                <.icon
                  name={if @show_summary, do: "hero-chevron-down", else: "hero-chevron-up"}
                  class="size-4"
                />
              </span>
            </span>
          </button>

          <div
            id="summary-sheet-body"
            class={[
              "overflow-y-auto transition-[max-height] duration-300 ease-out",
              if(@show_summary, do: "max-h-[55vh]", else: "max-h-0")
            ]}
          >
            <div class="px-5 pb-8 pt-1">
              <.summary attempt={@attempt} stats={@stats} />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :page, :integer, required: true
  attr :page_count, :integer, required: true
  attr :id, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <nav :if={@page_count > 1} class="flex flex-wrap gap-2 items-center" id={@id}>
      <button
        :for={index <- 1..@page_count}
        phx-click="goto_page"
        phx-value-page={index}
        class={[
          "btn btn-sm btn-circle",
          if(index == @page, do: "btn-primary", else: "btn-outline")
        ]}
        id={"#{@id}-page-#{index}"}
        title={"Página #{index}"}
      >
        {index}
      </button>
    </nav>
    """
  end

  attr :attempt, :map, required: true
  attr :stats, :map, required: true

  defp summary(assigns) do
    ~H"""
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

  # O card inteiro é tingido pelo resultado: verde correta, vermelho
  # incorreta, âmbar parcial/anulada, apagado para "não sei".
  defp result_state_class(question, answer, points) do
    cond do
      question.annulled -> "qstate-annulled"
      answer.state == :dont_know -> "qstate-dontknow"
      zero?(answer.score) -> "qstate-err"
      full?(answer.score, points) -> "qstate-ok"
      true -> "qstate-partial"
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
         socket
         |> assign(
           attempt: attempt,
           version: version,
           role: role,
           answers: answers,
           ordered_questions: ordered_questions,
           points: Scoring.question_points(version, version.questions),
           stats: stats(version, attempt, answers),
           show_summary: false
         )
         |> paginate(1)}
    end
  end

  def handle_event("goto_page", %{"page" => page}, socket) do
    {:noreply, paginate(socket, String.to_integer(page))}
  end

  def handle_event("toggle_summary", _params, socket) do
    {:noreply, update(socket, :show_summary, &(!&1))}
  end

  @per_page 10

  # Mesma paginação da tela de resposta: 10 questões por página, com a
  # numeração global preservada.
  defp paginate(socket, page) do
    ordered = socket.assigns.ordered_questions
    pages = Enum.chunk_every(ordered, @per_page)
    page_count = max(length(pages), 1)
    page = min(max(page, 1), page_count)

    page_questions =
      pages
      |> Enum.at(page - 1, [])
      |> Enum.map(fn question ->
        {question, Enum.find_index(ordered, &(&1.id == question.id))}
      end)

    assign(socket, page: page, page_count: page_count, page_questions: page_questions)
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
