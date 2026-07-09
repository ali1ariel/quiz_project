defmodule QuizProject.AI.Gemini do
  @moduledoc """
  Provider Google Gemini (generateContent). Configuração via variáveis de
  ambiente: `GEMINI_API_KEY` e opcionalmente `GEMINI_MODEL`
  (padrão gemini-2.0-flash).
  """
  @behaviour QuizProject.AI.Provider

  alias QuizProject.AI.OpenAI, as: SharedParsers
  alias QuizProject.AI.Prompts

  @impl true
  def generate_tags(statement) do
    with {:ok, body} <- generate(Prompts.tags_system(), Prompts.tags_user(statement)) do
      SharedParsers.parse_tags(body)
    end
  end

  @impl true
  def grade_text_answer(statement, reference, answer) do
    with {:ok, body} <-
           generate(Prompts.grade_system(), Prompts.grade_user(statement, reference, answer)) do
      SharedParsers.parse_grade(body)
    end
  end

  @impl true
  def generate_reference(statement) do
    with {:ok, body} <- generate(Prompts.reference_system(), Prompts.reference_user(statement)) do
      SharedParsers.parse_reference(body)
    end
  end

  @impl true
  def evaluate_progression(summary) do
    with {:ok, body} <-
           generate(Prompts.progression_system(), Prompts.progression_user(summary)) do
      SharedParsers.parse_evaluation(body)
    end
  end

  defp generate(system, user) do
    api_key = Application.get_env(:quiz_project, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      model = Application.get_env(:quiz_project, :gemini_model, "gemini-2.0-flash")

      request =
        Req.new(
          [
            url:
              "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent",
            headers: [{"x-goog-api-key", api_key}],
            json: %{
              system_instruction: %{parts: [%{text: system}]},
              contents: [%{role: "user", parts: [%{text: user}]}],
              generationConfig: %{response_mime_type: "application/json"}
            },
            receive_timeout: 60_000
          ] ++ Application.get_env(:quiz_project, :ai_req_options, [])
        )

      case Req.post(request) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          content =
            get_in(body, [
              "candidates",
              Access.at(0),
              "content",
              "parts",
              Access.at(0),
              "text"
            ])

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
