defmodule QuizProject.AI.OpenAI do
  @moduledoc """
  Provider OpenAI (Chat Completions). Configuração via variáveis de ambiente:
  `OPENAI_API_KEY` e opcionalmente `OPENAI_MODEL` (padrão gpt-5.5).
  """
  @behaviour QuizProject.AI.Provider

  alias QuizProject.AI.Prompts

  @impl true
  def generate_tags(statement) do
    with {:ok, body} <- chat(Prompts.tags_system(), Prompts.tags_user(statement)) do
      parse_tags(body)
    end
  end

  @impl true
  def grade_text_answer(statement, reference, answer) do
    with {:ok, body} <-
           chat(Prompts.grade_system(), Prompts.grade_user(statement, reference, answer)) do
      parse_grade(body)
    end
  end

  @impl true
  def generate_reference(statement) do
    with {:ok, body} <- chat(Prompts.reference_system(), Prompts.reference_user(statement)) do
      parse_reference(body)
    end
  end

  def parse_tags(%{"tags" => tags}) when is_list(tags) do
    {:ok, tags |> Enum.filter(&is_binary/1) |> Enum.take(4)}
  end

  def parse_tags(other), do: {:error, {:unexpected_response, other}}

  def parse_grade(%{"percent" => percent} = body) when is_number(percent) do
    {:ok, %{percent: round(percent), feedback: body["feedback"] || ""}}
  end

  def parse_grade(other), do: {:error, {:unexpected_response, other}}

  def parse_reference(%{"reference" => reference}) when is_binary(reference) do
    {:ok, reference}
  end

  def parse_reference(other), do: {:error, {:unexpected_response, other}}

  defp chat(system, user) do
    api_key = Application.get_env(:quiz_project, :openai_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      model = Application.get_env(:quiz_project, :openai_model, "gpt-5.5")

      request =
        Req.new(
          [
            url: "https://api.openai.com/v1/chat/completions",
            auth: {:bearer, api_key},
            json: %{
              model: model,
              response_format: %{type: "json_object"},
              messages: [
                %{role: "system", content: system},
                %{role: "user", content: user}
              ]
            },
            receive_timeout: 30_000
          ] ++ Application.get_env(:quiz_project, :ai_req_options, [])
        )

      case Req.post(request) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          content = get_in(body, ["choices", Access.at(0), "message", "content"])
          decode_json_content(content)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_json_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, {:invalid_json, content}}
    end
  end

  defp decode_json_content(other), do: {:error, {:unexpected_response, other}}
end
