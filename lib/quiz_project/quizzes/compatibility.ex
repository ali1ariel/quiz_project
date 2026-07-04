defmodule QuizProject.Quizzes.Compatibility do
  @moduledoc """
  Assinatura de compatibilidade de uma questão.

  O hash cobre exatamente os campos que afetam a estrutura da resposta:
  enunciado, tipo, alternativas (identidade, texto e quais são corretas),
  regra de nota parcial em múltiplas corretas, resposta de referência e a
  nota do editor quando usada como referência de correção (discursivas).

  Fora do hash (não quebram compatibilidade): peso, nota total, descrição,
  ordem das perguntas, tags de IA e metadados. Anulação é verificada à parte
  no reaproveitamento, pois pode acontecer depois da publicação.
  """

  def hash(question) do
    options =
      question.options
      |> Enum.sort_by(& &1.identity_key)
      |> Enum.map(&{&1.identity_key, &1.text, &1.correct})

    terms = %{
      statement: question.statement,
      type: question.type,
      allow_partial_credit: question.allow_partial_credit,
      true_false_answer: question.true_false_answer,
      reference_answer: question.reference_answer,
      editor_note: if(question.type == :text, do: question.editor_note),
      options: options
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(terms))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Uma resposta anterior pode ser reaproveitada quando a questão mantém a mesma
  assinatura e nenhuma das duas instâncias está anulada.
  """
  def compatible?(old_question, new_question) do
    not old_question.annulled and
      not new_question.annulled and
      is_binary(old_question.compatibility_hash) and
      old_question.compatibility_hash == new_question.compatibility_hash
  end
end
