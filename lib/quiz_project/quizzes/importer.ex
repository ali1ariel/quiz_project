defmodule QuizProject.Quizzes.Importer do
  @moduledoc """
  Importação de quiz via JSON. O quiz importado entra sempre como rascunho
  para revisão antes da publicação.

  Formato esperado (chaves em português):

      {
        "nome": "Meu quiz",
        "descricao": "Opcional",
        "nota_total": 100,
        "pesos_desiguais": false,
        "modo_ordem": "fixa" | "aleatoria" | "ia",
        "questoes": [
          {
            "enunciado": "Texto da pergunta",
            "tipo": "verdadeiro_falso" | "unica" | "multipla" | "discursiva",
            "resposta_verdadeiro_falso": true,
            "alternativas": [{"texto": "...", "correta": true}],
            "nota_parcial": true,
            "resposta_referencia": "Só para discursivas",
            "nota_editor": "Opcional",
            "peso": 10
          }
        ]
      }
  """

  @type_map %{
    "verdadeiro_falso" => :true_false,
    "unica" => :single,
    "multipla" => :multiple,
    "discursiva" => :text
  }

  @order_map %{"fixa" => :fixed, "aleatoria" => :random, "ia" => :ai}

  @doc """
  Valida e normaliza o JSON. Retorna `{:ok, attrs}` com os atributos prontos
  para criação do rascunho, ou `{:error, [mensagens]}`.
  """
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) ->
        parse(map)

      {:ok, _} ->
        {:error, ["O JSON precisa ser um objeto"]}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, ["JSON inválido: #{Exception.message(error)}"]}
    end
  end

  def parse(map) when is_map(map) do
    errors = validate_root(map)

    if errors == [] do
      {:ok, normalize(map)}
    else
      {:error, errors}
    end
  end

  defp validate_root(map) do
    List.flatten([
      if(!is_binary(map["nome"]) or String.trim(map["nome"]) == "",
        do: ["Campo \"nome\" é obrigatório"],
        else: []
      ),
      case map["questoes"] do
        questions when is_list(questions) and questions != [] ->
          questions |> Enum.with_index(1) |> Enum.flat_map(&validate_question/1)

        _ ->
          ["Campo \"questoes\" precisa ser uma lista com pelo menos uma questão"]
      end,
      case map["modo_ordem"] do
        nil -> []
        mode when is_map_key(@order_map, mode) -> []
        _ -> ["Campo \"modo_ordem\" deve ser \"fixa\", \"aleatoria\" ou \"ia\""]
      end,
      case map["nota_total"] do
        nil -> []
        n when is_number(n) and n > 0 -> []
        _ -> ["Campo \"nota_total\" deve ser um número positivo"]
      end
    ])
  end

  defp validate_question({question, index}) when is_map(question) do
    type = @type_map[question["tipo"]]

    List.flatten([
      if(!is_binary(question["enunciado"]) or String.trim(question["enunciado"]) == "",
        do: ["Questão #{index}: \"enunciado\" é obrigatório"],
        else: []
      ),
      if(is_nil(type),
        do: [
          "Questão #{index}: \"tipo\" deve ser \"verdadeiro_falso\", \"unica\", \"multipla\" ou \"discursiva\""
        ],
        else: []
      ),
      case type do
        :true_false ->
          if is_boolean(question["resposta_verdadeiro_falso"]),
            do: [],
            else: ["Questão #{index}: \"resposta_verdadeiro_falso\" deve ser true ou false"]

        :single ->
          validate_options(question, index, exactly_one_correct: true)

        :multiple ->
          validate_options(question, index, exactly_one_correct: false)

        _ ->
          []
      end,
      case question["peso"] do
        nil -> []
        n when is_number(n) and n >= 0 -> []
        _ -> ["Questão #{index}: \"peso\" deve ser um número não negativo"]
      end
    ])
  end

  defp validate_question({_question, index}), do: ["Questão #{index}: formato inválido"]

  defp validate_options(question, index, exactly_one_correct: exactly_one?) do
    case question["alternativas"] do
      options when is_list(options) and length(options) >= 2 ->
        invalid =
          Enum.any?(options, fn option ->
            not (is_map(option) and is_binary(option["texto"]))
          end)

        correct_count =
          Enum.count(options, fn option -> is_map(option) and option["correta"] == true end)

        List.flatten([
          if(invalid,
            do: ["Questão #{index}: cada alternativa precisa de \"texto\""],
            else: []
          ),
          cond do
            invalid ->
              []

            exactly_one? and correct_count != 1 ->
              ["Questão #{index}: marque exatamente 1 alternativa como correta"]

            not exactly_one? and correct_count < 1 ->
              ["Questão #{index}: marque pelo menos 1 alternativa como correta"]

            true ->
              []
          end
        ])

      _ ->
        ["Questão #{index}: \"alternativas\" precisa ser uma lista com pelo menos 2 itens"]
    end
  end

  defp normalize(map) do
    %{
      name: String.trim(map["nome"]),
      description: map["descricao"] || "",
      total_points: Decimal.new(to_string(map["nota_total"] || 100)),
      unequal_weights: map["pesos_desiguais"] == true,
      question_order_mode: @order_map[map["modo_ordem"]] || :fixed,
      questions:
        map["questoes"]
        |> Enum.with_index()
        |> Enum.map(fn {question, position} ->
          type = @type_map[question["tipo"]]

          %{
            position: position,
            statement: String.trim(question["enunciado"]),
            type: type,
            true_false_answer: if(type == :true_false, do: question["resposta_verdadeiro_falso"]),
            allow_partial_credit: type == :multiple and question["nota_parcial"] == true,
            reference_answer: if(type == :text, do: question["resposta_referencia"]),
            editor_note: question["nota_editor"],
            weight: if(question["peso"], do: Decimal.new(to_string(question["peso"]))),
            options:
              (question["alternativas"] || [])
              |> Enum.with_index()
              |> Enum.map(fn {option, option_position} ->
                %{
                  position: option_position,
                  text: option["texto"],
                  correct: option["correta"] == true
                }
              end)
          }
        end)
    }
  end
end
