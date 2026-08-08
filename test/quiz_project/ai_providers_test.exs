defmodule QuizProject.AIProvidersTest do
  use ExUnit.Case, async: false

  alias QuizProject.AI.{Claude, Gemini, OpenAI}

  setup do
    Application.put_env(:quiz_project, :ai_req_options,
      plug: {Req.Test, QuizProject.AIProvidersTest},
      retry: false
    )

    Application.put_env(:quiz_project, :openai_api_key, "chave-teste")
    Application.put_env(:quiz_project, :gemini_api_key, "chave-teste")
    Application.put_env(:quiz_project, :anthropic_api_key, "chave-teste")

    on_exit(fn ->
      Application.delete_env(:quiz_project, :ai_req_options)
      Application.delete_env(:quiz_project, :openai_api_key)
      Application.delete_env(:quiz_project, :gemini_api_key)
      Application.delete_env(:quiz_project, :anthropic_api_key)
    end)

    :ok
  end

  test "OpenAI: gera tags a partir da resposta da API" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{"message" => %{"content" => ~s({"tags": ["história", "brasil"]})}}
        ]
      })
    end)

    assert {:ok, ["história", "brasil"]} = OpenAI.generate_tags("Quem proclamou a república?")
  end

  test "OpenAI: corrige resposta discursiva" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{
            "message" => %{
              "content" => ~s({"percent": 75, "feedback": "Cobriu boa parte da referência."})
            }
          }
        ]
      })
    end)

    assert {:ok, %{percent: 75, feedback: "Cobriu boa parte da referência."}} =
             OpenAI.grade_text_answer("Enunciado", "Referência", "Resposta")
  end

  test "OpenAI: erro HTTP vira tupla de erro" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:error, {:http_error, 500, _}} = OpenAI.generate_tags("Enunciado")
  end

  test "OpenAI: sem API key retorna erro sem chamar HTTP" do
    Application.delete_env(:quiz_project, :openai_api_key)
    assert {:error, :missing_api_key} = OpenAI.generate_tags("Enunciado")
  end

  test "OpenAI: avalia progressão do participante" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{
            "message" => %{
              "content" =>
                ~s({"evaluation": "Você dominou as questões 1 e 2; a questão 3 segue incorreta."})
            }
          }
        ]
      })
    end)

    assert {:ok, "Você dominou as questões 1 e 2; a questão 3 segue incorreta."} =
             OpenAI.evaluate_progression("Quiz: Teste — versão 1\nNotas: 50%, 100%")
  end

  test "OpenAI: avaliação sem campo evaluation vira erro" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => ~s({"resultado": "ok"})}}]
      })
    end)

    assert {:error, {:unexpected_response, _}} = OpenAI.evaluate_progression("resumo")
  end

  test "Claude: gera tags ignorando o bloco de raciocínio que vem antes do texto" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{"type" => "thinking", "thinking" => ""},
          %{"type" => "text", "text" => ~s({"tags": ["biologia", "célula"]})}
        ]
      })
    end)

    assert {:ok, ["biologia", "célula"]} = Claude.generate_tags("O que é uma mitocôndria?")
  end

  test "Claude: aceita JSON embrulhado em bloco markdown" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" => "```json\n{\"reference\": \"A mitocôndria produz ATP.\"}\n```"
          }
        ]
      })
    end)

    assert {:ok, "A mitocôndria produz ATP."} = Claude.generate_reference("Enunciado")
  end

  test "Claude: recusa dos classificadores vira erro em vez de JSON inválido" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "refusal",
        "stop_details" => %{"type" => "refusal", "category" => "cyber"},
        "content" => []
      })
    end)

    assert {:error, {:refusal, %{"category" => "cyber"}}} = Claude.generate_tags("Enunciado")
  end

  test "Claude: resposta truncada em max_tokens vira erro explícito" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "max_tokens",
        "content" => [%{"type" => "text", "text" => ~s({"mindmap": [{"id": "node_1")}]
      })
    end)

    assert {:error, :max_tokens} = Claude.curate_mindmap("Texto longo de estudo")
  end

  test "Claude: texto sem nenhum JSON vira erro de parse" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => "Não consigo responder isso."}]
      })
    end)

    assert {:error, {:invalid_json, _}} = Claude.generate_tags("Enunciado")
  end

  test "Claude: erro HTTP vira tupla de erro" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "rate_limit_error"})
    end)

    assert {:error, {:http_error, 429, _}} = Claude.generate_tags("Enunciado")
  end

  test "Claude: sem API key retorna erro sem chamar HTTP" do
    Application.delete_env(:quiz_project, :anthropic_api_key)
    assert {:error, :missing_api_key} = Claude.generate_tags("Enunciado")
  end

  test "Claude: envia system no topo, max_tokens e a versão da API" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      assert ["2023-06-01"] = Plug.Conn.get_req_header(conn, "anthropic-version")
      assert ["chave-teste"] = Plug.Conn.get_req_header(conn, "x-api-key")
      assert body["system"] =~ "avaliador justo"
      assert [%{"role" => "user"}] = body["messages"]
      assert is_integer(body["max_tokens"])

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => ~s({"percent": 80, "feedback": "Bom."})}]
      })
    end)

    assert {:ok, %{percent: 80}} = Claude.grade_text_answer("Enunciado", "Ref", "Resposta")
  end

  test "Gemini: gera tags a partir da resposta da API" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "candidates" => [
          %{"content" => %{"parts" => [%{"text" => ~s({"tags": ["geografia"]})}]}}
        ]
      })
    end)

    assert {:ok, ["geografia"]} = Gemini.generate_tags("Qual o maior rio do mundo?")
  end

  test "Gemini: gera referência própria" do
    Req.Test.stub(QuizProject.AIProvidersTest, fn conn ->
      Req.Test.json(conn, %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [%{"text" => ~s({"reference": "O rio Amazonas é o maior do mundo."})}]
            }
          }
        ]
      })
    end)

    assert {:ok, "O rio Amazonas é o maior do mundo."} =
             Gemini.generate_reference("Qual o maior rio do mundo?")
  end
end
