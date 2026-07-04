defmodule QuizProject.Quizzes do
  @moduledoc """
  Domínio de quizzes: agrupador, versões, questões e alternativas.

  As funções públicas deste módulo são a única porta de entrada da camada
  web. Autorização de dono é verificada explicitamente aqui (o `actor` é o
  usuário logado); as ações Ash internas rodam com `authorize?: false`.
  """

  use Ash.Domain

  require Ash.Query

  alias QuizProject.Quizzes.{
    Importer,
    Option,
    Publisher,
    Question,
    Quiz,
    QuizVersion,
    Scoring
  }

  resources do
    resource Quiz
    resource QuizVersion
    resource Question
    resource Option
  end

  @version_load [questions: [:options]]

  ## Criação e edição de rascunho

  @doc "Cria um quiz novo com a versão 1 em rascunho. Requer usuário logado."
  def create_draft_quiz(%{id: owner_id}) do
    quiz =
      Quiz
      |> Ash.Changeset.for_create(:create, %{owner_id: owner_id}, authorize?: false)
      |> Ash.create!()

    version =
      QuizVersion
      |> Ash.Changeset.for_create(:create, %{quiz_id: quiz.id, version_number: 1},
        authorize?: false
      )
      |> Ash.create!()

    {:ok, %{version | quiz: quiz}}
  end

  @doc """
  Valida um JSON de importação sem criar nada. Retorna `{:ok, attrs}` com os
  dados normalizados (para pré-visualização) ou `{:error, mensagens}`.
  """
  def preview_import(json), do: Importer.parse(json)

  @doc "Importa um quiz de JSON. Entra como rascunho para revisão."
  def import_quiz(owner, json) do
    with {:ok, attrs} <- Importer.parse(json) do
      {:ok, version} = create_draft_quiz(owner)

      version =
        version
        |> Ash.Changeset.for_update(
          :update_draft,
          Map.take(attrs, [
            :name,
            :description,
            :total_points,
            :unequal_weights,
            :question_order_mode
          ]),
          authorize?: false
        )
        |> Ash.update!()

      Enum.each(attrs.questions, fn question_attrs ->
        {options, question_attrs} = Map.pop(question_attrs, :options)

        question =
          Question
          |> Ash.Changeset.for_create(
            :create,
            Map.put(question_attrs, :quiz_version_id, version.id),
            authorize?: false
          )
          |> Ash.create!()

        Enum.each(options, fn option_attrs ->
          Option
          |> Ash.Changeset.for_create(
            :create,
            Map.put(option_attrs, :question_id, question.id),
            authorize?: false
          )
          |> Ash.create!()
        end)
      end)

      {:ok, reload_version(version)}
    end
  end

  @doc "Atualiza dados básicos do rascunho (autosave)."
  def update_draft(version, attrs, actor) do
    with :ok <- authorize_owner(version, actor) do
      version
      |> Ash.Changeset.for_update(:update_draft, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  @doc """
  Cria ou atualiza uma questão do rascunho junto com suas alternativas.

  `options_attrs` é uma lista de mapas com `:id` (quando existente), `:text`,
  `:correct` e `:position`. Alternativas existentes são atualizadas (mantendo
  a identidade estável), novas são criadas e ausentes são removidas.
  """
  def upsert_question(version, question_attrs, options_attrs, actor) do
    with :ok <- authorize_owner(version, actor),
         :ok <- ensure_draft(version) do
      question =
        case question_attrs[:id] do
          nil ->
            position = Enum.count(load_questions(version))

            Question
            |> Ash.Changeset.for_create(
              :create,
              question_attrs
              |> Map.delete(:id)
              |> Map.merge(%{quiz_version_id: version.id, position: position}),
              authorize?: false
            )
            |> Ash.create!()

          id ->
            Question
            |> Ash.get!(id, authorize?: false)
            |> Ash.Changeset.for_update(:update, Map.delete(question_attrs, :id),
              authorize?: false
            )
            |> Ash.update!()
        end

      sync_options(question, options_attrs)
      {:ok, Ash.load!(question, [:options], reuse_values?: false, authorize?: false)}
    end
  end

  defp sync_options(question, options_attrs) do
    existing = Ash.load!(question, [:options], authorize?: false).options
    existing_by_id = Map.new(existing, &{&1.id, &1})
    kept_ids = options_attrs |> Enum.map(& &1[:id]) |> Enum.reject(&is_nil/1) |> MapSet.new()

    for option <- existing, not MapSet.member?(kept_ids, option.id) do
      Ash.destroy!(option, authorize?: false)
    end

    for attrs <- options_attrs do
      case attrs[:id] && existing_by_id[attrs[:id]] do
        nil ->
          Option
          |> Ash.Changeset.for_create(
            :create,
            attrs |> Map.delete(:id) |> Map.put(:question_id, question.id),
            authorize?: false
          )
          |> Ash.create!()

        option ->
          option
          |> Ash.Changeset.for_update(:update, Map.take(attrs, [:text, :correct, :position]),
            authorize?: false
          )
          |> Ash.update!()
      end
    end

    :ok
  end

  @doc "Remove uma questão do rascunho e reordena as demais."
  def delete_question(question, actor) do
    version = get_version!(question.quiz_version_id)

    with :ok <- authorize_owner(version, actor),
         :ok <- ensure_draft(version) do
      Ash.destroy!(question, authorize?: false)

      version
      |> load_questions()
      |> Enum.sort_by(& &1.position)
      |> Enum.with_index()
      |> Enum.each(fn {q, index} ->
        if q.position != index do
          q
          |> Ash.Changeset.for_update(:update, %{position: index}, authorize?: false)
          |> Ash.update!()
        end
      end)

      :ok
    end
  end

  @doc "Move uma questão do rascunho uma posição para cima ou para baixo."
  def move_question(question, direction, actor) when direction in [:up, :down] do
    version = get_version!(question.quiz_version_id)

    with :ok <- authorize_owner(version, actor),
         :ok <- ensure_draft(version) do
      questions = version |> load_questions() |> Enum.sort_by(& &1.position)
      index = Enum.find_index(questions, &(&1.id == question.id))
      target = if direction == :up, do: index - 1, else: index + 1

      if target >= 0 and target < length(questions) do
        neighbor = Enum.at(questions, target)

        swap_positions(question, neighbor)
      end

      :ok
    end
  end

  defp swap_positions(a, b) do
    {pos_a, pos_b} = {a.position, b.position}

    a
    |> Ash.Changeset.for_update(:update, %{position: pos_b}, authorize?: false)
    |> Ash.update!()

    b
    |> Ash.Changeset.for_update(:update, %{position: pos_a}, authorize?: false)
    |> Ash.update!()
  end

  ## Publicação e versionamento

  @doc "Publica o rascunho: valida, congela, gera tags de IA e changelog."
  def publish(version, actor) do
    with :ok <- authorize_owner(version, actor) do
      Publisher.publish(version)
    end
  end

  @doc """
  Garante um rascunho editável para o quiz: retorna o rascunho existente ou
  cria uma nova versão copiando a última publicada (mantendo identidades
  estáveis de questões e alternativas).
  """
  def ensure_draft(quiz_record, actor) when is_struct(quiz_record, Quiz) do
    with :ok <- authorize_owner(quiz_record, actor) do
      versions = list_versions(quiz_record)

      case Enum.find(versions, &(&1.status == :draft)) do
        nil ->
          case Enum.find(versions, &(&1.status == :published)) do
            nil -> {:error, :no_version}
            published -> {:ok, copy_as_draft(published)}
          end

        draft ->
          {:ok, draft}
      end
    end
  end

  defp copy_as_draft(published) do
    published = Ash.load!(published, @version_load, authorize?: false)
    next_number = next_version_number(published.quiz_id)

    draft =
      QuizVersion
      |> Ash.Changeset.for_create(
        :create,
        %{
          quiz_id: published.quiz_id,
          version_number: next_number,
          name: published.name,
          description: published.description,
          total_points: published.total_points,
          unequal_weights: published.unequal_weights,
          question_order_mode: published.question_order_mode
        },
        authorize?: false
      )
      |> Ash.create!()

    Enum.each(published.questions, fn question ->
      copy =
        Question
        |> Ash.Changeset.for_create(
          :create,
          %{
            quiz_version_id: draft.id,
            identity_key: question.identity_key,
            position: question.position,
            statement: question.statement,
            type: question.type,
            allow_partial_credit: question.allow_partial_credit,
            true_false_answer: question.true_false_answer,
            editor_note: question.editor_note,
            weight: question.weight,
            annulled: question.annulled,
            annulled_reason: question.annulled_reason
          },
          authorize?: false
        )
        |> Ash.create!()

      Enum.each(question.options, fn option ->
        Option
        |> Ash.Changeset.for_create(
          :create,
          %{
            question_id: copy.id,
            identity_key: option.identity_key,
            position: option.position,
            text: option.text,
            correct: option.correct
          },
          authorize?: false
        )
        |> Ash.create!()
      end)
    end)

    reload_version(draft)
  end

  defp next_version_number(quiz_id) do
    QuizVersion
    |> Ash.Query.filter(quiz_id == ^quiz_id)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> 1
      version -> version.version_number + 1
    end
  end

  @doc """
  Anula uma questão de forma retroativa: a anulação corrige algo que não
  deveria existir, então vale para a mesma questão (casada por `identity_key`)
  em todas as versões do quiz e re-corrige as tentativas já finalizadas,
  concedendo pontuação integral. Registra o motivo e uma entrada no changelog
  da versão em que a ação foi disparada.
  """
  def annul_question(question, reason, actor) do
    version = get_version!(question.quiz_version_id)

    with :ok <- authorize_owner(version, actor) do
      if version.status != :published do
        {:error, :not_published}
      else
        annul_across_versions(version.quiz_id, question.identity_key, true, reason)

        annulled = Ash.get!(Question, question.id, authorize?: false)
        entry = QuizProject.Quizzes.Changelog.annulment_entry(annulled)

        version
        |> Ash.Changeset.for_update(:set_changelog, %{changelog: version.changelog ++ [entry]},
          authorize?: false
        )
        |> Ash.update!()

        {:ok, annulled}
      end
    end
  end

  @doc """
  Anula ou reverte a anulação de uma questão a partir do editor. Assim como
  `annul_question/3`, a anulação é retroativa: propaga para a mesma questão
  (por `identity_key`) em todas as versões e re-corrige as tentativas
  finalizadas. Reverter volta a nota ao valor corrigido original.
  """
  def set_question_annulment(question, annulled?, reason, actor) do
    version = get_version!(question.quiz_version_id)

    with :ok <- authorize_owner(version, actor),
         :ok <- ensure_draft(version) do
      annul_across_versions(version.quiz_id, question.identity_key, annulled?, reason)
      {:ok, Ash.get!(Question, question.id, authorize?: false)}
    end
  end

  # Aplica (ou reverte) a anulação da questão `identity_key` em todas as versões
  # do quiz e re-corrige as tentativas finalizadas afetadas. A re-correção passa
  # pelo `Grader`, que dá pontuação integral quando anulada e recalcula a nota
  # normal quando revertida.
  defp annul_across_versions(quiz_id, identity_key, annulled?, reason) do
    version_ids =
      QuizVersion
      |> Ash.Query.filter(quiz_id == ^quiz_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    Enum.each(version_ids, fn version_id ->
      full = get_version_full!(version_id)

      case Enum.find(full.questions, &(&1.identity_key == identity_key)) do
        nil ->
          :ok

        question ->
          question
          |> Ash.Changeset.for_update(:set_annulment, %{annulled: annulled?, reason: reason},
            authorize?: false
          )
          |> Ash.update!()

          points = Scoring.question_points(full, full.questions)[question.id]
          regraded = %{question | annulled: annulled?, annulled_reason: if(annulled?, do: reason)}

          if points, do: QuizProject.Attempts.regrade_question(regraded, points)
      end
    end)
  end

  @doc "Ativa ou desativa o quiz. Desativado não aceita novas respostas."
  def set_quiz_active(quiz_record, active?, actor) do
    with :ok <- authorize_owner(quiz_record, actor) do
      quiz_record
      |> Ash.Changeset.for_update(:set_active, %{active: active?}, authorize?: false)
      |> Ash.update()
    end
  end

  ## Exclusão

  @doc """
  Deleta um rascunho. Se o quiz ficar sem nenhuma versão, o quiz inteiro é
  removido. Versões publicadas nunca são apagadas por aqui.
  """
  def delete_draft(version, actor) do
    with :ok <- authorize_owner(version, actor),
         :ok <- ensure_draft(version) do
      quiz_id = version.quiz_id
      Ash.destroy!(version, authorize?: false)

      remaining =
        QuizVersion
        |> Ash.Query.filter(quiz_id == ^quiz_id)
        |> Ash.count!(authorize?: false)

      if remaining == 0 do
        Quiz |> Ash.get!(quiz_id, authorize?: false) |> Ash.destroy!(authorize?: false)
        {:ok, :quiz_deleted}
      else
        {:ok, :draft_deleted}
      end
    end
  end

  @doc "Deleta o quiz inteiro (todas as versões)."
  def delete_quiz(quiz_record, actor) do
    with :ok <- authorize_owner(quiz_record, actor) do
      Ash.destroy!(quiz_record, authorize?: false)
      :ok
    end
  end

  ## Consultas

  @doc "Quizzes criados pelo usuário, com versões carregadas (mais recente primeiro)."
  def list_created(%{id: owner_id}) do
    Quiz
    |> Ash.Query.filter(owner_id == ^owner_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(:versions)
    |> Ash.read!(authorize?: false)
  end

  def get_quiz!(id), do: Ash.get!(Quiz, id, load: [:versions], authorize?: false)

  def get_version!(id), do: Ash.get!(QuizVersion, id, authorize?: false)

  @doc "Versão com quiz, questões e alternativas carregados."
  def get_version_full!(id) do
    Ash.get!(QuizVersion, id, load: [:quiz] ++ @version_load, authorize?: false)
  end

  def list_versions(quiz_record) do
    QuizVersion
    |> Ash.Query.filter(quiz_id == ^quiz_record.id)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Histórico de versões publicadas (mais recente primeiro)."
  def version_history(quiz_record) do
    QuizVersion
    |> Ash.Query.filter(quiz_id == ^quiz_record.id and status == :published)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Resolve um link público: retorna a versão publicada mais recente do quiz
  com aquele slug, com questões carregadas.
  """
  def get_public_by_slug(slug) do
    quiz_record =
      Quiz
      |> Ash.Query.filter(public_slug == ^slug)
      |> Ash.read_one!(authorize?: false)

    with %Quiz{} <- quiz_record,
         %QuizVersion{} = version <- latest_published_version(quiz_record) do
      {:ok, {quiz_record, Ash.load!(version, @version_load, authorize?: false)}}
    else
      _ -> {:error, :not_found}
    end
  end

  def latest_published_version(quiz_record) do
    QuizVersion
    |> Ash.Query.filter(quiz_id == ^quiz_record.id and status == :published)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  def get_question!(id), do: Ash.get!(Question, id, load: [:options], authorize?: false)

  ## Autorização e apoio

  def authorize_owner(%Quiz{} = quiz_record, actor) do
    if actor && quiz_record.owner_id == actor.id, do: :ok, else: {:error, :unauthorized}
  end

  def authorize_owner(%QuizVersion{} = version, actor) do
    authorize_owner(Ash.get!(Quiz, version.quiz_id, authorize?: false), actor)
  end

  defp ensure_draft(%QuizVersion{status: :draft}), do: :ok
  defp ensure_draft(%QuizVersion{}), do: {:error, :not_draft}

  defp load_questions(version) do
    Question
    |> Ash.Query.filter(quiz_version_id == ^version.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp reload_version(version) do
    Ash.get!(QuizVersion, version.id, load: [:quiz] ++ @version_load, authorize?: false)
  end
end
