defmodule QuizProjectWeb.QuizEvolutionLive do
  @moduledoc """
  Estatísticas do participante em um quiz que ele respondeu: evolução das
  notas e comparação questão por questão entre as tentativas.

  Versões não se misturam: cada versão do quiz é tratada como um quiz
  próprio, com sua linha evolutiva, suas estatísticas e sua comparação de
  respostas — mesmo que uma questão pareça idêntica em duas versões, as
  respostas pertencem a versões diferentes.
  """
  use QuizProjectWeb, :live_view

  import QuizProjectWeb.EvolutionChart

  alias QuizProject.AI
  alias QuizProject.Attempts
  alias QuizProject.Quizzes.Scoring

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      notifications={@notifications}
      active_nav={:quizzes}
      wide
    >
      <div class="flex items-center gap-3 flex-wrap">
        <.link navigate={~p"/painel"} class="btn btn-sm btn-ghost rounded-full">
          <.icon name="hero-arrow-left" class="size-4" /> Voltar
        </.link>
        <h1 class="text-2xl font-bold truncate">{@quiz_name}</h1>
        <span class="badge badge-ghost rounded-full">
          {@total} {if @total == 1, do: "tentativa", else: "tentativas"}
        </span>
      </div>

      <p class="text-sm opacity-70">
        Sua evolução neste quiz, versão por versão. Cada versão é avaliada
        separadamente: as respostas não se misturam entre versões, mesmo
        quando a questão parece a mesma.
      </p>

      <div
        :for={section <- @sections}
        id={"evolution-v#{section.number}"}
        class="card qcard bg-base-200 p-4 space-y-4"
      >
        <div class="flex items-center gap-2 flex-wrap">
          <span class="badge badge-neutral rounded-full">versão {section.number}</span>
          <span :if={section.name && section.name != @quiz_name} class="font-semibold truncate">
            {section.name}
          </span>
          <span class="text-xs opacity-70">
            {length(section.attempts)} {if length(section.attempts) == 1,
              do: "tentativa finalizada",
              else: "tentativas finalizadas"}
          </span>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div class="rounded-xl bg-base-100 p-3">
            <p class="text-xs opacity-70">Última nota</p>
            <p class="text-xl font-semibold">{format_decimal(section.stats.last)}%</p>
          </div>
          <div class="rounded-xl bg-base-100 p-3">
            <p class="text-xs opacity-70">Melhor nota</p>
            <p class="text-xl font-semibold">{format_decimal(section.stats.best)}%</p>
          </div>
          <div class="rounded-xl bg-base-100 p-3">
            <p class="text-xs opacity-70">Média</p>
            <p class="text-xl font-semibold">{format_decimal(section.stats.avg)}%</p>
          </div>
          <div class="rounded-xl bg-base-100 p-3">
            <p class="text-xs opacity-70">Progresso</p>
            <p class={["text-xl font-semibold", delta_class(section.stats.delta)]}>
              {delta_text(section.stats.delta)}
            </p>
          </div>
        </div>

        <.evolution_chart
          :if={section.chart}
          chart={section.chart}
          id={"evolution-chart-v#{section.number}"}
        />
        <p :if={!section.chart} class="text-xs opacity-70">
          Responda esta versão mais de uma vez para ver a linha evolutiva.
        </p>

        <div class="space-y-3">
          <h2 class="font-semibold text-sm uppercase tracking-wide opacity-70">
            Questão por questão
          </h2>

          <div
            :for={{entry, index} <- Enum.with_index(section.questions, 1)}
            id={"evolution-v#{section.number}-q#{entry.question.id}"}
            class="rounded-xl border border-base-300 p-3 space-y-2"
          >
            <div class="flex items-start gap-2 flex-wrap">
              <span class="badge badge-neutral badge-sm rounded-full mt-0.5">{index}</span>
              <p class="font-medium flex-1 min-w-0 break-words">{entry.question.statement}</p>
              <span
                :if={entry.question.annulled}
                class="badge badge-warning badge-sm rounded-full"
              >
                anulada
              </span>
            </div>

            <p class="text-xs opacity-70">
              {type_label(entry.question.type)} · vale {format_decimal(entry.points)} pts
              · correta em {entry.correct_count} de {length(entry.entries)}
              {if length(entry.entries) == 1, do: "tentativa", else: "tentativas"} · {trend_label(
                entry.trend
              )}
            </p>

            <div
              :if={entry.question.type != :text}
              class="rounded-lg bg-base-100 p-2 text-sm"
            >
              <p class="text-xs font-semibold opacity-70 mb-1">Resposta correta</p>
              <.correct_answer question={entry.question} />
            </div>

            <ol class="space-y-2">
              <li
                :for={item <- entry.entries}
                id={"evolution-answer-#{item.answer.id}"}
                class="rounded-lg bg-base-100 p-2"
              >
                <div class="flex items-center gap-2 flex-wrap text-xs">
                  <span class="font-semibold">{ordinal(item.index)} tentativa</span>
                  <span class="opacity-70">{Calendar.strftime(item.date, "%d/%m/%Y")}</span>
                  <span class={["badge badge-xs rounded-full", status_class(item.status)]}>
                    {status_label(item.status)}
                  </span>
                  <span class="opacity-70">
                    {format_decimal(item.answer.score)}/{format_decimal(entry.points)} pts
                  </span>
                </div>

                <div class="text-sm mt-1">
                  <.user_answer question={entry.question} answer={item.answer} />
                </div>

                <div
                  :if={item.answer.ai_feedback}
                  class="mt-2 rounded-lg bg-base-200 p-2 text-xs space-y-1"
                >
                  <p class="font-semibold">
                    Correção da IA{if item.answer.ai_percent,
                      do: " — #{item.answer.ai_percent}% de acerto"}
                  </p>
                  <p class="whitespace-pre-wrap">{item.answer.ai_feedback}</p>
                  <p :if={item.answer.ai_reference_generated && item.answer.ai_reference}>
                    <span class="font-semibold">Referência usada:</span>
                    {item.answer.ai_reference}
                  </p>
                </div>
              </li>
            </ol>

            <div
              :if={entry.question.type == :text && length(entry.entries) >= 2}
              class="space-y-2"
            >
              <button
                :if={
                  !@evaluations[entry.question.id] &&
                    !MapSet.member?(@evaluating, entry.question.id)
                }
                id={"evaluate-question-#{entry.question.id}"}
                phx-click="evaluate_question"
                phx-value-question-id={entry.question.id}
                class="btn btn-sm btn-outline rounded-full"
              >
                <.icon name="hero-sparkles" class="size-4" /> Avaliar minha evolução com IA
              </button>

              <div
                :if={MapSet.member?(@evaluating, entry.question.id)}
                id={"evaluating-question-#{entry.question.id}"}
                class="flex items-center gap-2 text-sm opacity-70"
              >
                <span class="loading loading-spinner loading-sm"></span>
                Comparando suas respostas a esta questão…
              </div>

              <div
                :if={@evaluations[entry.question.id]}
                id={"evaluation-question-#{entry.question.id}"}
                class="rounded-lg bg-base-100 border border-base-300 p-3 space-y-1"
              >
                <p class="text-xs font-semibold opacity-70 flex items-center gap-1">
                  <.icon name="hero-sparkles" class="size-3" />
                  Avaliação da IA sobre sua evolução nesta questão
                </p>
                <p class="text-sm whitespace-pre-wrap">{@evaluations[entry.question.id]}</p>
              </div>

              <p :if={@evaluation_errors[entry.question.id]} class="text-xs text-error">
                {@evaluation_errors[entry.question.id]}
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :question, :map, required: true
  attr :answer, :map, required: true

  defp user_answer(assigns) do
    ~H"""
    <div>
      <%= cond do %>
        <% @answer.state == :dont_know -> %>
          <p class="italic opacity-70">Não sei a resposta</p>
        <% @answer.payload in [nil, %{}] -> %>
          <p class="italic opacity-70">Sem resposta</p>
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
          <p class="opacity-70 italic">Correção por IA com base na referência</p>
      <% end %>
    </div>
    """
  end

  def mount(%{"quiz_id" => quiz_id}, _session, socket) do
    attempts = load_attempts(socket.assigns.current_user, quiz_id)

    if attempts == [] do
      {:ok,
       socket
       |> put_flash(:error, "Você ainda não finalizou nenhuma tentativa nesse quiz.")
       |> push_navigate(to: ~p"/painel")}
    else
      {:ok,
       socket
       |> assign(
         quiz_id: quiz_id,
         evaluating: MapSet.new(),
         evaluations: %{},
         evaluation_errors: %{}
       )
       |> assign_attempts(attempts)}
    end
  end

  defp load_attempts(user, quiz_id) do
    user
    |> Attempts.list_finished_for_participant(quiz_id)
    |> Enum.filter(&(&1.percent != nil and &1.finished_at != nil))
  end

  defp assign_attempts(socket, attempts) do
    quiz_name = quiz_name(attempts)

    assign(socket,
      quiz_name: quiz_name,
      total: length(attempts),
      sections: build_sections(attempts),
      page_title: build_title(["Evolução", quiz_name])
    )
  end

  def handle_event("evaluate_question", %{"question-id" => question_id}, socket) do
    send(self(), {:evaluate_question, question_id})

    {:noreply,
     socket
     |> update(:evaluating, &MapSet.put(&1, question_id))
     |> update(:evaluation_errors, &Map.delete(&1, question_id))}
  end

  # Correção em background terminou (broadcast assinado pelo hook
  # :notify_attempts): se for deste quiz, a nova tentativa entra nas
  # estatísticas ao vivo, sem recarregar a página.
  def handle_info({:attempt_finished, %{quiz_id: quiz_id}}, socket) do
    if quiz_id == socket.assigns.quiz_id do
      attempts = load_attempts(socket.assigns.current_user, quiz_id)
      {:noreply, assign_attempts(socket, attempts)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:evaluate_question, question_id}, socket) do
    entry = find_question_entry(socket.assigns.sections, question_id)

    socket =
      case AI.evaluate_progression(question_summary(entry)) do
        {:ok, evaluation} ->
          update(socket, :evaluations, &Map.put(&1, question_id, evaluation))

        {:error, _reason} ->
          update(
            socket,
            :evaluation_errors,
            &Map.put(
              &1,
              question_id,
              "Não foi possível avaliar sua evolução agora. Tente de novo."
            )
          )
      end

    {:noreply, update(socket, :evaluating, &MapSet.delete(&1, question_id))}
  end

  defp find_question_entry(sections, question_id) do
    sections
    |> Enum.flat_map(& &1.questions)
    |> Enum.find(&(&1.question.id == question_id))
  end

  # Resumo enviado à IA: o enunciado da questão discursiva e as respostas do
  # participante em ordem cronológica, cada uma com nota e feedback da
  # correção. A referência do criador não é incluída, pois a avaliação volta
  # para o participante.
  defp question_summary(entry) do
    answers =
      Enum.map_join(entry.entries, "\n\n", fn item ->
        text =
          case item.answer do
            %{state: :dont_know} -> "(respondeu \"não sei\")"
            %{payload: payload} when payload in [nil, %{}] -> "(não respondeu)"
            %{payload: payload} -> payload["text"] |> to_string() |> String.slice(0, 600)
          end

        feedback =
          if item.answer.ai_feedback,
            do: "\nFeedback da correção: #{item.answer.ai_feedback}",
            else: ""

        "#{item.index}ª resposta (#{Calendar.strftime(item.date, "%d/%m/%Y")}, " <>
          "#{format_decimal(item.answer.score)}/#{format_decimal(entry.points)} pts" <>
          "#{if item.answer.ai_percent, do: ", correção: #{item.answer.ai_percent}%"}):\n" <>
          text <> feedback
      end)

    "Questão discursiva: #{entry.question.statement}\n\n" <> answers
  end

  defp quiz_name(attempts) do
    latest = Enum.max_by(attempts, & &1.quiz_version.version_number)

    case latest.quiz_version.name do
      name when name in [nil, ""] -> "Quiz sem nome"
      name -> name
    end
  end

  # Uma seção por versão (mais recente primeiro), cada uma com estatísticas,
  # linha evolutiva e comparação por questão calculadas só com as tentativas
  # daquela versão.
  defp build_sections(attempts) do
    attempts
    |> Enum.group_by(& &1.quiz_version.version_number)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.map(fn {number, version_attempts} ->
      version = hd(version_attempts).quiz_version
      points = Scoring.question_points(version, version.questions)
      finished = Enum.sort_by(version_attempts, & &1.finished_at, DateTime)

      %{
        number: number,
        name: version.name,
        attempts: finished,
        chart: chart_data(finished, w: 720, h: 180),
        stats: section_stats(finished),
        questions: build_questions(version, finished, points)
      }
    end)
  end

  defp section_stats(finished) do
    percents = Enum.map(finished, & &1.percent)
    total = Enum.reduce(percents, Decimal.new(0), &Decimal.add/2)

    %{
      last: List.last(percents),
      best: Enum.max_by(percents, &Decimal.to_float/1),
      avg: Decimal.div(total, Decimal.new(length(percents))),
      delta: if(length(percents) > 1, do: Decimal.sub(List.last(percents), hd(percents)))
    }
  end

  # Para cada questão da versão (na ordem original), a lista cronológica das
  # respostas do participante — a comparação "resposta por resposta".
  defp build_questions(version, finished, points) do
    version.questions
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn question ->
      entries =
        finished
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {attempt, attempt_index} ->
          case Enum.find(attempt.answers, &(&1.question_id == question.id)) do
            nil ->
              []

            answer ->
              [
                %{
                  index: attempt_index,
                  date: attempt.finished_at,
                  answer: answer,
                  status: answer_status(question, answer, points[question.id])
                }
              ]
          end
        end)

      %{
        question: question,
        points: points[question.id],
        entries: entries,
        correct_count: Enum.count(entries, &(&1.status == :correct)),
        trend: question_trend(question, entries)
      }
    end)
  end

  defp answer_status(question, answer, points) do
    cond do
      question.annulled -> :annulled
      answer.state == :dont_know -> :dont_know
      zero?(answer.score) -> :incorrect
      full?(answer.score, points) -> :correct
      true -> :partial
    end
  end

  defp zero?(nil), do: true
  defp zero?(score), do: Decimal.compare(score, Decimal.new(0)) != :gt

  defp full?(nil, _points), do: false
  defp full?(_score, nil), do: false
  defp full?(score, points), do: Decimal.compare(score, points) != :lt

  defp status_class(:correct), do: "badge-success"
  defp status_class(:partial), do: "badge-warning"
  defp status_class(:incorrect), do: "badge-error"
  defp status_class(:dont_know), do: "badge-ghost"
  defp status_class(:annulled), do: "badge-warning"

  defp status_label(:correct), do: "correta"
  defp status_label(:partial), do: "parcialmente correta"
  defp status_label(:incorrect), do: "incorreta"
  defp status_label(:dont_know), do: "não sei"
  defp status_label(:annulled), do: "anulada"

  # Resumo da trajetória na questão, comparando o primeiro e o último status.
  defp question_trend(%{annulled: true}, _entries), do: :annulled

  defp question_trend(_question, entries) do
    ranks = Enum.map(entries, &status_rank(&1.status))

    cond do
      length(ranks) < 2 -> :single
      Enum.all?(ranks, &(&1 == 2)) -> :always_correct
      List.last(ranks) > hd(ranks) -> :improved
      List.last(ranks) < hd(ranks) -> :declined
      true -> :stable
    end
  end

  defp status_rank(:correct), do: 2
  defp status_rank(:partial), do: 1
  defp status_rank(_), do: 0

  defp trend_label(:annulled), do: "questão anulada"
  defp trend_label(:single), do: "uma tentativa até agora"
  defp trend_label(:always_correct), do: "sempre correta"
  defp trend_label(:improved), do: "você evoluiu nesta questão"
  defp trend_label(:declined), do: "você regrediu nesta questão"
  defp trend_label(:stable), do: "resultado estável"

  defp delta_class(nil), do: nil

  defp delta_class(delta) do
    case Decimal.compare(delta, Decimal.new(0)) do
      :gt -> "text-success"
      :lt -> "text-error"
      :eq -> nil
    end
  end

  defp delta_text(nil), do: "—"

  defp delta_text(delta) do
    signal = if Decimal.compare(delta, Decimal.new(0)) == :gt, do: "+", else: ""
    "#{signal}#{format_decimal(delta)}%"
  end

  defp type_label(:true_false), do: "Verdadeiro ou falso"
  defp type_label(:single), do: "Uma correta"
  defp type_label(:multiple), do: "Múltiplas corretas"
  defp type_label(:text), do: "Discursiva"

  defp ordinal(1), do: "1ª"
  defp ordinal(2), do: "2ª"
  defp ordinal(3), do: "3ª"
  defp ordinal(n), do: "#{n}ª"

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
