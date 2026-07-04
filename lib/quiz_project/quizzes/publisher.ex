defmodule QuizProject.Quizzes.Publisher do
  @moduledoc """
  Publicação de uma versão de quiz: valida, gera tags internas de IA por
  questão, calcula a assinatura de compatibilidade, monta o changelog em
  relação à versão publicada anterior e congela a versão.
  """

  require Ash.Query

  alias QuizProject.AI
  alias QuizProject.Quizzes.{Changelog, Compatibility, QuizVersion}

  @doc """
  Publica a versão. Retorna `{:ok, version}` ou `{:error, [mensagens]}`.
  """
  def publish(version) do
    version = Ash.load!(version, [questions: [:options]], authorize?: false)

    with :ok <- ensure_draft(version),
         :ok <- validate(version) do
      questions = Enum.sort_by(version.questions, & &1.position)

      Enum.each(questions, fn question ->
        tags =
          case AI.generate_tags(question.statement) do
            {:ok, tags} -> tags
            {:error, _} -> []
          end

        question
        |> Ash.Changeset.for_update(
          :set_publication_data,
          %{ai_tags: tags, compatibility_hash: Compatibility.hash(question)},
          authorize?: false
        )
        |> Ash.update!()
      end)

      # recarrega para o changelog comparar os dados finais
      version =
        Ash.load!(version, [questions: [:options]], reuse_values?: false, authorize?: false)

      changelog = Changelog.diff(previous_published(version), version)

      published =
        version
        |> Ash.Changeset.for_update(:mark_published, %{changelog: changelog}, authorize?: false)
        |> Ash.update!()

      {:ok, published}
    end
  end

  defp ensure_draft(%{status: :draft}), do: :ok
  defp ensure_draft(_), do: {:error, ["Esta versão já foi publicada"]}

  @doc "Valida a versão para publicação. Retorna :ok ou {:error, [mensagens]}."
  def validate(version) do
    questions = Enum.sort_by(version.questions, & &1.position)

    errors =
      List.flatten([
        if(String.trim(version.name || "") == "", do: ["O quiz precisa de um nome"], else: []),
        if(questions == [], do: ["O quiz precisa de pelo menos uma questão"], else: []),
        if(Decimal.compare(version.total_points, Decimal.new(0)) != :gt,
          do: ["A nota total deve ser maior que zero"],
          else: []
        ),
        Enum.flat_map(questions, &question_errors/1),
        weight_errors(version, questions)
      ])

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp question_errors(question) do
    number = question.position + 1
    options = question.options

    List.flatten([
      if(String.trim(question.statement || "") == "",
        do: ["Questão #{number}: enunciado vazio"],
        else: []
      ),
      case question.type do
        :true_false ->
          if is_nil(question.true_false_answer),
            do: ["Questão #{number}: defina se a afirmação é verdadeira ou falsa"],
            else: []

        :single ->
          List.flatten([
            if(length(options) < 2,
              do: ["Questão #{number}: precisa de pelo menos 2 alternativas"],
              else: []
            ),
            if(Enum.count(options, & &1.correct) != 1,
              do: ["Questão #{number}: marque exatamente 1 alternativa correta"],
              else: []
            )
          ])

        :multiple ->
          List.flatten([
            if(length(options) < 2,
              do: ["Questão #{number}: precisa de pelo menos 2 alternativas"],
              else: []
            ),
            if(Enum.count(options, & &1.correct) < 1,
              do: ["Questão #{number}: marque pelo menos 1 alternativa correta"],
              else: []
            )
          ])

        :text ->
          []
      end,
      if(question.weight && Decimal.compare(question.weight, Decimal.new(0)) == :lt,
        do: ["Questão #{number}: peso não pode ser negativo"],
        else: []
      )
    ])
  end

  defp weight_errors(%{unequal_weights: false}, _questions), do: []

  defp weight_errors(version, questions) do
    used =
      questions
      |> Enum.map(& &1.weight)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.compare(used, version.total_points) == :gt do
      ["A soma dos pesos definidos (#{used}) excede a nota total (#{version.total_points})"]
    else
      []
    end
  end

  @doc "Versão publicada imediatamente anterior à dada, com questões carregadas."
  def previous_published(version) do
    QuizVersion
    |> Ash.Query.filter(
      quiz_id == ^version.quiz_id and status == :published and
        version_number < ^version.version_number
    )
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load(questions: [:options])
    |> Ash.read_one!(authorize?: false)
  end
end
