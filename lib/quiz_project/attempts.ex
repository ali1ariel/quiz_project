defmodule QuizProject.Attempts do
  @moduledoc """
  Domínio de tentativas: iniciar, responder, limpar/restaurar, marcar para
  depois, "não sei", finalizar com correção e reaproveitamento de respostas
  compatíveis entre versões.

  O participante é identificado por `%{user: usuário_ou_nil, token: token}`.
  Usuário logado tem continuidade entre dispositivos; anônimo, apenas
  enquanto mantiver o token de sessão.
  """

  use Ash.Domain

  require Ash.Query

  alias QuizProject.Attempts.{Answer, Attempt, Grader}
  alias QuizProject.Quizzes
  alias QuizProject.Quizzes.{Compatibility, Scoring, TagOrdering}

  resources do
    resource Attempt
    resource Answer
  end

  @attempt_load [answers: [], quiz_version: [:quiz, questions: [:options]]]

  ## Início e retomada

  @doc """
  Inicia uma tentativa em uma versão publicada. Define e congela a ordem das
  questões conforme o modo da versão e reaproveita respostas compatíveis da
  tentativa finalizada mais recente do participante em outras versões.
  """
  def start_attempt(version, participant, display_identity) do
    version = Ash.load!(version, [questions: [:options]], authorize?: false)

    if version.status != :published do
      {:error, :not_published}
    else
      questions = Enum.sort_by(version.questions, & &1.position)
      order = question_order(version, questions)

      attempt =
        Attempt
        |> Ash.Changeset.for_create(
          :start,
          %{
            quiz_version_id: version.id,
            user_id: participant.user && participant.user.id,
            participant_token: participant.token,
            display_identity: display_identity,
            question_order: order
          },
          authorize?: false
        )
        |> Ash.create()

      case attempt do
        {:ok, attempt} ->
          Enum.each(questions, fn question ->
            Answer
            |> Ash.Changeset.for_create(
              :create,
              %{attempt_id: attempt.id, question_id: question.id},
              authorize?: false
            )
            |> Ash.create!()
          end)

          import_previous_answers(attempt, version, participant)
          {:ok, get_attempt_full!(attempt.id)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp question_order(version, questions) do
    ordered =
      case version.question_order_mode do
        :fixed -> questions
        :random -> Enum.shuffle(questions)
        :ai -> TagOrdering.order(questions)
      end

    Enum.map(ordered, & &1.id)
  end

  @doc "Tentativa em andamento do participante nesta versão, se houver."
  def find_in_progress(version, participant) do
    Attempt
    |> Ash.Query.filter(quiz_version_id == ^version.id and status == :in_progress)
    |> filter_participant(participant)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp filter_participant(query, %{user: user}) when not is_nil(user) do
    Ash.Query.filter(query, user_id == ^user.id)
  end

  defp filter_participant(query, %{token: token}) when is_binary(token) do
    Ash.Query.filter(query, participant_token == ^token and is_nil(user_id))
  end

  ## Reaproveitamento entre versões

  defp import_previous_answers(attempt, version, participant) do
    case previous_finished_attempt(version, participant) do
      nil ->
        :ok

      previous ->
        previous_questions = Map.new(previous.quiz_version.questions, &{&1.id, &1})

        previous_answers_by_identity =
          previous.answers
          |> Enum.filter(&(&1.state == :answered and &1.payload not in [nil, %{}]))
          |> Enum.flat_map(fn answer ->
            case previous_questions[answer.question_id] do
              nil -> []
              question -> [{question.identity_key, {question, answer}}]
            end
          end)
          |> Map.new()

        new_answers = Ash.load!(attempt, [:answers], authorize?: false).answers
        new_answers_by_question = Map.new(new_answers, &{&1.question_id, &1})

        for question <- version.questions,
            {old_question, old_answer} <- [previous_answers_by_identity[question.identity_key]],
            not is_nil(old_question),
            Compatibility.compatible?(old_question, question) do
          new_answers_by_question[question.id]
          |> Ash.Changeset.for_update(
            :save,
            %{state: :answered, payload: old_answer.payload, imported_from_previous: true},
            authorize?: false
          )
          |> Ash.update!()
        end

        :ok
    end
  end

  defp previous_finished_attempt(version, participant) do
    Attempt
    |> Ash.Query.filter(
      quiz_version.quiz_id == ^version.quiz_id and
        quiz_version_id != ^version.id and
        status == :finished
    )
    |> filter_participant(participant)
    |> Ash.Query.sort(finished_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:answers, quiz_version: [questions: [:options]]])
    |> Ash.read_one!(authorize?: false)
  end

  ## Respostas

  @doc """
  Salva uma resposta. O payload é validado contra o tipo da questão. Editar
  uma resposta importada remove a marcação de importada.
  """
  def save_answer(attempt, answer, question, payload) do
    with :ok <- ensure_in_progress(attempt),
         {:ok, normalized} <- normalize_payload(question, payload) do
      answer
      |> Ash.Changeset.for_update(
        :save,
        %{
          state: :answered,
          payload: normalized,
          # responder desmarca automaticamente o "responder depois";
          # o participante pode remarcar sem perder a resposta
          marked_later: false,
          imported_from_previous: false,
          cleared_backup: nil,
          cleared_at: nil
        },
        authorize?: false
      )
      |> Ash.update()
    end
  end

  defp normalize_payload(%{type: :true_false}, %{"value" => value}) when is_boolean(value) do
    {:ok, %{"value" => value}}
  end

  defp normalize_payload(%{type: :single} = question, %{"option" => key}) do
    if Enum.any?(question.options, &(&1.identity_key == key)) do
      {:ok, %{"option" => key}}
    else
      {:error, :invalid_payload}
    end
  end

  defp normalize_payload(%{type: :multiple} = question, %{"options" => keys})
       when is_list(keys) and keys != [] do
    valid_keys = MapSet.new(question.options, & &1.identity_key)

    if Enum.all?(keys, &MapSet.member?(valid_keys, &1)) do
      {:ok, %{"options" => Enum.uniq(keys)}}
    else
      {:error, :invalid_payload}
    end
  end

  defp normalize_payload(%{type: :text}, %{"text" => text}) when is_binary(text) do
    if String.trim(text) == "" do
      {:error, :invalid_payload}
    else
      {:ok, %{"text" => text}}
    end
  end

  defp normalize_payload(_question, _payload), do: {:error, :invalid_payload}

  @doc "Alterna a marca de responder depois."
  def toggle_marked_later(attempt, answer) do
    with :ok <- ensure_in_progress(attempt) do
      answer
      |> Ash.Changeset.for_update(:save, %{marked_later: !answer.marked_later}, authorize?: false)
      |> Ash.update()
    end
  end

  @doc """
  Alterna "não sei a resposta". Só é permitido quando não há resposta
  preenchida. Conta como resposta final válida com nota zero.
  """
  def toggle_dont_know(attempt, answer) do
    with :ok <- ensure_in_progress(attempt) do
      case answer.state do
        :answered ->
          {:error, :has_answer}

        :dont_know ->
          answer
          |> Ash.Changeset.for_update(:save, %{state: :unanswered}, authorize?: false)
          |> Ash.update()

        :unanswered ->
          answer
          |> Ash.Changeset.for_update(:save, %{state: :dont_know, payload: nil},
            authorize?: false
          )
          |> Ash.update()
      end
    end
  end

  @doc """
  Limpa a resposta preenchida guardando backup para restauração. A janela de
  10 segundos do botão "Restaurar" é controlada pela interface.
  """
  def clear_answer(attempt, answer) do
    with :ok <- ensure_in_progress(attempt) do
      if answer.state in [:answered, :dont_know] do
        answer
        |> Ash.Changeset.for_update(
          :save,
          %{
            state: :unanswered,
            payload: nil,
            cleared_backup: answer.payload,
            cleared_at: DateTime.utc_now(),
            imported_from_previous: false
          },
          authorize?: false
        )
        |> Ash.update()
      else
        {:error, :nothing_to_clear}
      end
    end
  end

  @doc "Restaura a resposta limpa, se houver backup."
  def restore_answer(attempt, answer) do
    with :ok <- ensure_in_progress(attempt) do
      case answer.cleared_backup do
        backup when is_map(backup) and backup != %{} ->
          answer
          |> Ash.Changeset.for_update(
            :save,
            %{state: :answered, payload: backup, cleared_backup: nil, cleared_at: nil},
            authorize?: false
          )
          |> Ash.update()

        _ ->
          {:error, :nothing_to_restore}
      end
    end
  end

  ## Finalização e correção

  @doc """
  Contagem de pendências: questões sem resposta e questões marcadas para
  responder depois (ainda sem resposta).
  """
  def pending_summary(attempt) do
    answers = Ash.load!(attempt, [:answers], reuse_values?: false, authorize?: false).answers

    %{
      unanswered: Enum.count(answers, &(&1.state == :unanswered and not &1.marked_later)),
      later: Enum.count(answers, &(&1.state == :unanswered and &1.marked_later))
    }
  end

  @doc """
  Finaliza a tentativa. Sem `force: true`, retorna `{:error, {:pending, resumo}}`
  se houver questões sem resposta. Com `force: true`, converte todas as
  pendências em "não sei" e finaliza. Depois de finalizada, a tentativa
  nunca mais pode ser editada.
  """
  def finalize(attempt, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    with :ok <- ensure_in_progress(attempt) do
      attempt = get_attempt_full!(attempt.id)
      pending = Enum.filter(attempt.answers, &(&1.state == :unanswered))

      cond do
        pending != [] and not force? ->
          {:error, {:pending, pending_summary(attempt)}}

        true ->
          Enum.each(pending, fn answer ->
            answer
            |> Ash.Changeset.for_update(:save, %{state: :dont_know, payload: nil},
              authorize?: false
            )
            |> Ash.update!()
          end)

          grade_and_finish(get_attempt_full!(attempt.id))
      end
    end
  end

  defp grade_and_finish(attempt) do
    version = attempt.quiz_version
    questions = Map.new(version.questions, &{&1.id, &1})
    points = Scoring.question_points(version, version.questions)

    total =
      attempt.answers
      |> Enum.map(fn answer ->
        question = Map.fetch!(questions, answer.question_id)
        result = Grader.grade(question, answer, Map.fetch!(points, question.id))

        answer
        |> Ash.Changeset.for_update(:set_grade, result, authorize?: false)
        |> Ash.update!()

        result.score
      end)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    max = Scoring.max_score(version, version.questions)

    percent =
      if Decimal.compare(max, Decimal.new(0)) == :gt do
        total |> Decimal.mult(Decimal.new(100)) |> Decimal.div(max) |> Decimal.round(1)
      else
        Decimal.new(0)
      end

    finished =
      attempt
      |> Ash.Changeset.for_update(
        :finish,
        %{score: total, max_score: max, percent: percent},
        authorize?: false
      )
      |> Ash.update!()

    {:ok, get_attempt_full!(finished.id)}
  end

  defp ensure_in_progress(%Attempt{status: :in_progress}), do: :ok
  defp ensure_in_progress(%Attempt{}), do: {:error, :finished}

  @doc """
  Re-corrige as tentativas finalizadas que responderam `question` (uma linha de
  questão de uma versão específica) e recalcula a nota de cada tentativa. É a
  base da anulação retroativa: com a questão anulada o `Grader` concede a
  pontuação integral; ao reverter, ele recalcula a nota normal a partir da
  resposta. As demais questões da tentativa não são reavaliadas.
  """
  def regrade_question(question, points) do
    Answer
    |> Ash.Query.filter(question_id == ^question.id)
    |> Ash.Query.load(:attempt)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(&1.attempt && &1.attempt.status == :finished))
    |> Enum.each(fn answer ->
      result = Grader.grade(question, answer, points)

      answer
      |> Ash.Changeset.for_update(:set_grade, result, authorize?: false)
      |> Ash.update!()

      recompute_totals(answer.attempt_id)
    end)

    :ok
  end

  defp recompute_totals(attempt_id) do
    attempt = Ash.get!(Attempt, attempt_id, load: [:answers], authorize?: false)

    total =
      Enum.reduce(attempt.answers, Decimal.new(0), fn answer, acc ->
        Decimal.add(acc, answer.score || Decimal.new(0))
      end)

    max = attempt.max_score || Decimal.new(0)

    percent =
      if Decimal.compare(max, Decimal.new(0)) == :gt do
        total |> Decimal.mult(Decimal.new(100)) |> Decimal.div(max) |> Decimal.round(1)
      else
        Decimal.new(0)
      end

    attempt
    |> Ash.Changeset.for_update(:set_totals, %{score: total, max_score: max, percent: percent},
      authorize?: false
    )
    |> Ash.update!()
  end

  ## Associação de tentativas anônimas à conta

  @doc """
  Associa ao usuário as tentativas anônimas vinculadas ao token de sessão.
  Chamado quando o participante cria conta ou loga durante a resposta.
  """
  def adopt_anonymous_attempts(user, participant_token) when is_binary(participant_token) do
    Attempt
    |> Ash.Query.filter(participant_token == ^participant_token and is_nil(user_id))
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn attempt ->
      attempt
      |> Ash.Changeset.for_update(:adopt, %{user_id: user.id}, authorize?: false)
      |> Ash.update!()
    end)

    :ok
  end

  def adopt_anonymous_attempts(_user, _participant_token), do: :ok

  ## Consultas e autorização

  def get_attempt_full!(id) do
    Ash.get!(Attempt, id, load: @attempt_load, authorize?: false)
  end

  @doc "Participante pode acessar a tentativa se for dele (conta ou token)."
  def authorize_participant(attempt, participant) do
    cond do
      participant.user && attempt.user_id == participant.user.id -> :ok
      is_binary(participant.token) and attempt.participant_token == participant.token -> :ok
      true -> {:error, :unauthorized}
    end
  end

  @doc "Tentativas do usuário logado (aba \"Quizzes respondidos\")."
  def list_answered(%{id: user_id}) do
    Attempt
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(quiz_version: [:quiz])
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Tentativas finalizadas de todas as versões de um quiz, para o criador.
  Expõe apenas a identificação escolhida pelo participante.
  """
  def list_attempts_for_quiz(quiz, actor) do
    with :ok <- Quizzes.authorize_owner(quiz, actor) do
      {:ok,
       Attempt
       |> Ash.Query.filter(quiz_version.quiz_id == ^quiz.id and status == :finished)
       |> Ash.Query.sort(finished_at: :desc)
       |> Ash.Query.load(quiz_version: [])
       |> Ash.read!(authorize?: false)}
    end
  end

  @doc """
  Status visual de uma página de questões.

    * `:green` — todas as questões finalizadas (respondidas ou "não sei");
    * `:yellow` — alguma questão marcada para responder depois;
    * `:red` — só após a tentativa de confirmação (`validated?`), quando
      restam questões sem resposta e sem marca de "depois";
    * `:neutral` — página incompleta ainda não validada (não mexida ou em
      andamento).
  """
  def page_status(answers, validated? \\ false) do
    cond do
      Enum.all?(answers, &(&1.state in [:answered, :dont_know])) ->
        :green

      validated? and Enum.any?(answers, &(&1.state == :unanswered and not &1.marked_later)) ->
        :red

      Enum.any?(answers, & &1.marked_later) ->
        :yellow

      true ->
        :neutral
    end
  end
end
