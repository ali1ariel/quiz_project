defmodule QuizProject.AI.Fake do
  @moduledoc """
  Provider determinístico para desenvolvimento e testes, sem chamadas HTTP.

  Tags: palavras mais relevantes do enunciado. Correção discursiva:
  similaridade de vocabulário (Jaccard) entre resposta e referência.
  """
  @behaviour QuizProject.AI.Provider

  @stopwords ~w(
    a o as os um uma uns umas de do da dos das em no na nos nas por para com
    sem sob sobre e ou que se ao aos à às é são foi ser estar como qual quais
    quando onde quem cujo cuja isso isto aquilo ele ela eles elas seu sua seus
    suas nem mais menos muito pouco também já não sim entre até desde
  )

  @impl true
  def generate_tags(statement) do
    tags =
      statement
      |> tokenize()
      |> Enum.frequencies()
      |> Enum.sort_by(fn {word, freq} -> {-freq, -String.length(word), word} end)
      |> Enum.take(4)
      |> Enum.map(fn {word, _} -> word end)

    {:ok, tags}
  end

  @impl true
  def grade_text_answer(_statement, reference, answer) do
    reference_tokens = MapSet.new(tokenize(reference))
    answer_tokens = MapSet.new(tokenize(answer))

    percent =
      cond do
        MapSet.size(answer_tokens) == 0 ->
          0

        MapSet.size(reference_tokens) == 0 ->
          0

        true ->
          intersection = MapSet.intersection(reference_tokens, answer_tokens) |> MapSet.size()
          union = MapSet.union(reference_tokens, answer_tokens) |> MapSet.size()
          round(intersection / union * 100)
      end

    feedback =
      cond do
        percent >= 80 ->
          "A resposta cobre os principais pontos da referência."

        percent >= 40 ->
          "A resposta aborda parte dos pontos esperados, mas deixa lacunas em relação à referência."

        true ->
          "A resposta diverge substancialmente da referência esperada."
      end

    {:ok,
     %{percent: percent, feedback: feedback <> " (avaliação heurística local, sem IA externa)"}}
  end

  @impl true
  def evaluate_progression(summary) do
    answers = summary |> String.split(~r/\dª resposta/) |> length() |> Kernel.-(1)

    {:ok,
     "Foram comparadas #{answers} respostas suas para a mesma questão. " <>
       "Confira o feedback de cada correção para ver quais lacunas apontadas " <>
       "você já fechou e quais persistem na resposta mais recente. " <>
       "(avaliação heurística local, sem IA externa)"}
  end

  @impl true
  def generate_reference(statement) do
    {:ok,
     "Resposta de referência gerada automaticamente a partir do enunciado: " <>
       "espera-se que o participante aborde diretamente o que é pedido em \"#{String.slice(statement, 0, 160)}\"."}
  end

  @impl true
  def curate_mindmap(text) do
    paragraphs =
      text
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    paragraphs = if paragraphs == [], do: [text], else: paragraphs

    # Agrupa os parágrafos em ramos para o mapa mental sair ramificado em vez de
    # uma raiz com dezenas de filhos rasos — é o formato que as visões de
    # navegação (árvore e rede) esperam.
    branches =
      paragraphs
      |> Enum.with_index(1)
      |> Enum.chunk_every(3)
      |> Enum.with_index(1)
      |> Enum.map(fn {chunk, branch_idx} ->
        leaves =
          Enum.map(chunk, fn {paragraph, idx} ->
            %{
              "id" => "node_#{branch_idx}_#{idx}",
              "label" => fake_label(paragraph, idx),
              "description" => "Conteúdo do parágrafo #{idx}",
              "content" => paragraph,
              "order" => idx,
              "node_type" => if(rem(idx, 2) == 0, do: "exemplo", else: "conceito"),
              "priority" => if(rem(idx, 2) == 0, do: "high", else: "medium"),
              "complexity" => "moderate",
              "user_notes" => "",
              "enabled" => true,
              "relations" =>
                if(idx > 1,
                  do: [
                    %{
                      "target_id" => "node_1_1",
                      "type" => "prerequisito",
                      "label" => "retoma a abertura"
                    }
                  ],
                  else: []
                ),
              "children" => []
            }
          end)

        %{
          "id" => "node_#{branch_idx}",
          "label" => "Bloco #{branch_idx}",
          "description" => "Agrupamento de #{length(leaves)} trecho(s) do material",
          "content" => "",
          "order" => 0,
          "node_type" => "conceito",
          "priority" => "high",
          "complexity" => "moderate",
          "user_notes" => "",
          "enabled" => true,
          "relations" => [],
          "children" => leaves
        }
      end)

    children = branches

    first_words = text |> String.slice(0, 50) |> String.trim()

    title = if first_words == "", do: "Material de Estudo", else: "Estudo: " <> first_words

    {:ok,
     %{
       "suggested_title" => title,
       "summary" => "Resumo do conteúdo com #{length(paragraphs)} seções identificadas.",
       "key_concepts" => [
         %{
           "term" => "Conceito 1",
           "definition" => "Definição do conceito principal extraído do texto."
         }
       ],
       "mindmap" => [
         %{
           "id" => "node_root",
           "label" => "Visão Geral do Conteúdo",
           "description" => "Estrutura principal do texto",
           "content" => "",
           "order" => 0,
           "node_type" => "conceito",
           "priority" => "high",
           "complexity" => "moderate",
           "user_notes" => "",
           "enabled" => true,
           "relations" => [],
           "children" => children
         }
       ]
     }}
  end

  defp fake_label(paragraph, idx) do
    case paragraph |> String.slice(0, 40) |> String.trim() do
      "" -> "Tópico #{idx}"
      label -> label <> "..."
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split()
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 3))
  end
end
