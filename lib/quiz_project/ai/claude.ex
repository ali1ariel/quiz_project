defmodule QuizProject.AI.Claude do
  @moduledoc """
  Provider Anthropic (Claude, Messages API). Configuração via variáveis de
  ambiente: `ANTHROPIC_API_KEY` e opcionalmente `ANTHROPIC_MODEL`. O modelo
  padrão fica em `config/config.exs`; ver `priv/docs/modelos_de_ia.md`.
  """
  @behaviour QuizProject.AI.Provider

  alias QuizProject.AI.OpenAI, as: SharedParsers
  alias QuizProject.AI.Prompts

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  # `max_tokens` é obrigatório na Messages API e limita raciocínio e texto
  # somados, então cada chamada reserva o tamanho da saída mais folga. O esforço
  # acompanha o quanto a tarefa depende de julgamento.
  @fast [max_tokens: 4_096, effort: "low"]
  @reasoned [max_tokens: 8_192, effort: "medium"]
  @mindmap [max_tokens: 64_000, effort: "high"]

  @impl true
  def generate_tags(statement) do
    with {:ok, body, _usage} <-
           message(Prompts.tags_system(), Prompts.tags_user(statement), @fast) do
      SharedParsers.parse_tags(body)
    end
  end

  @impl true
  def grade_text_answer(statement, reference, answer) do
    with {:ok, body, _usage} <-
           message(
             Prompts.grade_system(),
             Prompts.grade_user(statement, reference, answer),
             @reasoned
           ) do
      SharedParsers.parse_grade(body)
    end
  end

  @impl true
  def generate_reference(statement) do
    with {:ok, body, _usage} <-
           message(Prompts.reference_system(), Prompts.reference_user(statement), @fast) do
      SharedParsers.parse_reference(body)
    end
  end

  @impl true
  def evaluate_progression(summary) do
    with {:ok, body, _usage} <-
           message(Prompts.progression_system(), Prompts.progression_user(summary), @reasoned) do
      SharedParsers.parse_evaluation(body)
    end
  end

  @impl true
  def curate_mindmap(text, opts \\ []) do
    with {:ok, body, usage} <-
           message(
             Prompts.curate_mindmap_system(),
             Prompts.curate_mindmap_user(text),
             Keyword.merge(@mindmap, Keyword.take(opts, [:model]))
           ),
         {:ok, resultado} <- SharedParsers.parse_mindmap(body) do
      {:ok, resultado, usage}
    end
  end

  require Logger

  defp message(system, user, opts) do
    api_key = Application.get_env(:quiz_project, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      Logger.error("[AI.Claude] Chave de API ausente! Verifique a variável ANTHROPIC_API_KEY.")
      {:error, :missing_api_key}
    else
      model = Keyword.get(opts, :model) || Application.get_env(:quiz_project, :anthropic_model)
      Logger.info("[AI.Claude] Enviando requisição para Anthropic (modelo: #{model})...")

      request =
        Req.new(
          [
            url: @api_url,
            headers: [{"x-api-key", api_key}, {"anthropic-version", @api_version}],
            json: %{
              model: model,
              max_tokens: Keyword.fetch!(opts, :max_tokens),
              output_config: %{effort: Keyword.fetch!(opts, :effort)},
              # Na Messages API o prompt de sistema é campo de topo, não uma
              # mensagem com papel "system" como em OpenAI.
              system: system,
              messages: [%{role: "user", content: user}]
            },
            receive_timeout: :infinity
          ] ++ Application.get_env(:quiz_project, :ai_req_options, [])
        )

      case Req.post(request) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          Logger.info("[AI.Claude] Resposta HTTP 200 recebida com sucesso da Anthropic.")
          handle_message(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error(
            "[AI.Claude] Erro HTTP #{status} retornado pela Anthropic: #{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error(
            "[AI.Claude] Erro de conexão/rede na chamada Anthropic: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  # Recusa e truncamento chegam como HTTP 200. Sem estes dois casos a recusa
  # viraria "JSON inválido" e o truncamento passaria como conteúdo perdido sem
  # explicação.
  defp handle_message(%{"stop_reason" => "refusal"} = body) do
    Logger.error(
      "[AI.Claude] Requisição recusada pelos classificadores: #{inspect(body["stop_details"])}"
    )

    {:error, {:refusal, body["stop_details"]}}
  end

  defp handle_message(%{"stop_reason" => "max_tokens"}) do
    Logger.error("[AI.Claude] Resposta truncada no limite de max_tokens; o JSON veio incompleto.")
    {:error, :max_tokens}
  end

  # `content` é uma lista de blocos: com o raciocínio ligado (padrão no Opus 5)
  # o bloco de texto não é necessariamente o primeiro.
  defp handle_message(%{"content" => blocks} = body) when is_list(blocks) do
    with %{"text" => text} <- Enum.find(blocks, &(is_map(&1) and &1["type"] == "text")),
         {:ok, mapa} <- decode_json_content(text) do
      {:ok, mapa, usage(body)}
    else
      {:error, motivo} -> {:error, motivo}
      _ -> {:error, {:unexpected_response, blocks}}
    end
  end

  defp handle_message(other), do: {:error, {:unexpected_response, other}}

  # O raciocínio entra em `output_tokens`, e é boa parte do custo da curadoria —
  # por isso o número medido aqui vale mais que qualquer estimativa nossa.
  defp usage(%{"usage" => %{"input_tokens" => entrada, "output_tokens" => saida}})
       when is_integer(entrada) and is_integer(saida) do
    %{input: entrada, output: saida}
  end

  defp usage(_body), do: nil

  # A Messages API não tem o equivalente ao `response_format` da OpenAI nem ao
  # `response_mime_type` do Gemini: o JSON vem só da instrução do prompt, então a
  # resposta pode chegar cercada por bloco markdown ou por uma frase de abertura.
  defp decode_json_content(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> decode_embedded_json(text)
    end
  end

  defp decode_json_content(other), do: {:error, {:unexpected_response, other}}

  defp decode_embedded_json(text) do
    with [json] <- Regex.run(~r/\{.*\}/s, text),
         {:ok, map} when is_map(map) <- Jason.decode(json) do
      {:ok, map}
    else
      _ -> {:error, {:invalid_json, text}}
    end
  end
end
