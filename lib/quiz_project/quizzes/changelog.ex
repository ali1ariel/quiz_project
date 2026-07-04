defmodule QuizProject.Quizzes.Changelog do
  @moduledoc """
  Changelog simples entre duas versões de um quiz, comparando questões pela
  identidade estável (`identity_key`). Sem diff detalhado — apenas frases
  como "Questão 3 removida" ou "Peso da questão 2 alterado".
  """

  @doc """
  Compara a versão anterior (publicada) com a nova. Ambas devem vir com
  questões e alternativas carregadas. Retorna lista de frases.
  """
  def diff(nil, _new_version), do: ["Primeira versão publicada"]

  def diff(old_version, new_version) do
    old_questions = Map.new(old_version.questions, &{&1.identity_key, &1})
    new_questions = Map.new(new_version.questions, &{&1.identity_key, &1})

    removed =
      for q <- old_version.questions, not Map.has_key?(new_questions, q.identity_key) do
        "Questão #{label(q)} removida"
      end

    added =
      for q <- new_version.questions, not Map.has_key?(old_questions, q.identity_key) do
        "Questão #{label(q)} adicionada"
      end

    changed =
      new_version.questions
      |> Enum.flat_map(fn new_q ->
        case Map.get(old_questions, new_q.identity_key) do
          nil -> []
          old_q -> question_changes(old_q, new_q)
        end
      end)

    version_changes =
      List.flatten([
        if(Decimal.compare(old_version.total_points, new_version.total_points) != :eq,
          do: [
            "Nota total alterada de #{trim(old_version.total_points)} para #{trim(new_version.total_points)}"
          ],
          else: []
        ),
        if(old_version.question_order_mode != new_version.question_order_mode,
          do: ["Modo de ordenação das questões alterado"],
          else: []
        )
      ])

    entries = removed ++ added ++ changed ++ version_changes

    if entries == [], do: ["Sem mudanças estruturais"], else: entries
  end

  defp question_changes(old_q, new_q) do
    List.flatten([
      if(old_q.statement != new_q.statement,
        do: ["Enunciado da questão #{label(new_q)} alterado"],
        else: []
      ),
      if(old_q.type != new_q.type, do: ["Tipo da questão #{label(new_q)} alterado"], else: []),
      if(options_signature(old_q) != options_signature(new_q),
        do: ["Alternativas da questão #{label(new_q)} alteradas"],
        else: []
      ),
      if(old_q.true_false_answer != new_q.true_false_answer,
        do: ["Resposta da questão #{label(new_q)} alterada"],
        else: []
      ),
      if(old_q.editor_note != new_q.editor_note,
        do: ["Resposta de referência da questão #{label(new_q)} alterada"],
        else: []
      ),
      if(not old_q.annulled and new_q.annulled,
        do: ["Questão #{label(new_q)} anulada"],
        else: []
      ),
      if(old_q.annulled and not new_q.annulled,
        do: ["Anulação da questão #{label(new_q)} removida"],
        else: []
      ),
      if(weight_changed?(old_q, new_q),
        do: ["Peso da questão #{label(new_q)} alterado"],
        else: []
      ),
      if(old_q.allow_partial_credit != new_q.allow_partial_credit,
        do: ["Regra de nota parcial da questão #{label(new_q)} alterada"],
        else: []
      )
    ])
  end

  defp weight_changed?(%{weight: nil}, %{weight: nil}), do: false
  defp weight_changed?(%{weight: nil}, _), do: true
  defp weight_changed?(_, %{weight: nil}), do: true
  defp weight_changed?(old_q, new_q), do: Decimal.compare(old_q.weight, new_q.weight) != :eq

  defp options_signature(question) do
    question.options
    |> Enum.sort_by(& &1.identity_key)
    |> Enum.map(&{&1.identity_key, &1.text, &1.correct})
  end

  defp label(question), do: question.position + 1

  defp trim(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  @doc """
  Frase usada quando uma questão publicada é anulada diretamente (sem nova versão).
  """
  def annulment_entry(question), do: "Questão #{label(question)} anulada"
end
