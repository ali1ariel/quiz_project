defmodule QuizProject.AIProvidersTest do
  use ExUnit.Case, async: false

  alias QuizProject.AI
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

  # O catálogo de modelos envelhece sozinho: preço muda, modelo é desligado. Um
  # padrão apontando para modelo fora da tabela já aconteceu (`gemini-2.0-flash`,
  # desligado em 2026-06-01) e passou despercebido porque nada olhava.
  describe "catálogo de modelos" do
    setup do
      provider = Application.get_env(:quiz_project, :ai_provider)
      modelo = Application.get_env(:quiz_project, :anthropic_model)

      on_exit(fn ->
        Application.put_env(:quiz_project, :ai_provider, provider)
        Application.put_env(:quiz_project, :anthropic_model, modelo)
      end)

      :ok
    end

    test "todo modelo padrão está tabelado com preço" do
      for {modulo, chave, nome} <- [
            {OpenAI, :openai_model, "OpenAI"},
            {Gemini, :gemini_model, "Gemini"},
            {Claude, :anthropic_model, "Claude"}
          ] do
        Application.put_env(:quiz_project, :ai_provider, modulo)
        info = AI.runtime_info()

        assert info.provider == nome
        assert info.model == Application.get_env(:quiz_project, chave)

        assert %{input: entrada, output: saida} = info.pricing,
               "modelo padrão #{inspect(info.model)} está fora de @models — " <>
                 "ver priv/docs/modelos_de_ia.md"

        assert entrada > 0 and saida > 0
      end
    end

    test "custo sai do preço por milhão de tokens" do
      Application.put_env(:quiz_project, :ai_provider, Claude)
      Application.put_env(:quiz_project, :anthropic_model, "claude-opus-5")

      # 1M de entrada a US$ 5 mais 1M de saída a US$ 25.
      assert {:ok, custo} = AI.estimate_cost(1_000_000, 1_000_000)
      assert_in_delta custo, 30.0, 0.001
    end

    test "modelo fora da tabela não inventa preço nem janela" do
      Application.put_env(:quiz_project, :ai_provider, Claude)
      Application.put_env(:quiz_project, :anthropic_model, "claude-que-nao-existe")

      assert %{model: "claude-que-nao-existe", pricing: nil, context: nil} = AI.runtime_info()
      assert AI.estimate_cost(1000, 1000) == :unknown
    end

    test "provider local não anuncia modelo" do
      Application.put_env(:quiz_project, :ai_provider, QuizProject.AI.Fake)

      assert %{model: nil, pricing: nil, context: nil} = AI.runtime_info()
    end

    test "catálogo lista os provedores com disponibilidade e modelos" do
      catalogo = AI.catalog()
      slugs = Enum.map(catalogo, & &1.slug)

      assert slugs == ["claude", "openai", "gemini", "fake"]

      claude = Enum.find(catalogo, &(&1.slug == "claude"))

      # A chave veio do setup deste arquivo.
      assert claude.available?
      assert "claude-opus-5" in Enum.map(claude.models, & &1.id)

      # Mais capaz primeiro: quem escolhe tropeça no que dá conta antes do que
      # é barato.
      assert List.first(claude.models).tier == :frontier
      assert List.last(claude.models).tier == :light

      # O Fake não usa chave e está sempre disponível — e não tem modelo.
      fake = Enum.find(catalogo, &(&1.slug == "fake"))
      assert fake.available?
      assert fake.models == []
    end

    # A regra de entrada da tabela é cobertura de faixa, não histórico de versão:
    # sem isto, apagar modelo antigo pode deixar um provedor sem opção capaz — foi
    # o que aconteceu com o Gemini quando o critério era "atual e anterior".
    test "todo provedor cobre da faixa capaz à econômica" do
      for provider <- AI.catalog(), provider.models != [] do
        faixas = provider.models |> Enum.map(& &1.tier) |> Enum.uniq()

        assert :light in faixas, "#{provider.slug} não tem opção econômica"
        assert :balanced in faixas, "#{provider.slug} não tem opção intermediária"

        assert :flagship in faixas or :frontier in faixas,
               "#{provider.slug} não tem opção capaz"
      end
    end

    test "cada faixa de cada provedor tem uma versão só" do
      for provider <- AI.catalog(), provider.models != [] do
        por_faixa = Enum.group_by(provider.models, & &1.tier)

        for {faixa, modelos} <- por_faixa do
          assert length(modelos) == 1,
                 "#{provider.slug} tem #{length(modelos)} modelos na faixa #{faixa}: " <>
                   "#{Enum.map_join(modelos, ", ", & &1.id)} — ver priv/docs/modelos_de_ia.md"
        end
      end
    end

    test "provedor sem chave aparece no catálogo, mas indisponível" do
      Application.delete_env(:quiz_project, :gemini_api_key)

      refute AI.available?("gemini")
      assert Enum.any?(AI.catalog(), &(&1.slug == "gemini" and not &1.available?))
    end

    test "resolve recusa provedor e modelo de fora do catálogo" do
      assert {:error, :unknown_provider} = AI.resolve("provedor-que-nao-existe", nil)

      # Modelo existe, mas é de outro provedor: recusado do mesmo jeito, senão
      # bastaria adulterar o formulário para mandar a Anthropic um id da OpenAI.
      assert {:error, :unknown_model} = AI.resolve("claude", "gpt-5.6-sol")
      assert {:error, :unknown_model} = AI.resolve("claude", "modelo-inventado")
    end

    test "resolve devolve preço, janela e faixa do modelo escolhido" do
      assert {:ok, info} = AI.resolve("claude", "claude-opus-5")
      assert info.module == Claude
      assert info.pricing == %{input: 5.0, output: 25.0}
      assert info.context == 1_000_000
      assert info.tier == :flagship

      assert {:ok, fraco} = AI.resolve("claude", "claude-haiku-4-5")
      assert fraco.tier == :light
    end

    test "sem modelo, resolve cai no padrão do provedor" do
      assert {:ok, info} = AI.resolve("claude", nil)
      assert info.model == Application.get_env(:quiz_project, :anthropic_model)
    end

    test "custo acompanha o modelo escolhido, sem trocar a configuração global" do
      global = AI.provider()

      {:ok, caro} = AI.resolve("claude", "claude-opus-5")
      {:ok, barato} = AI.resolve("claude", "claude-haiku-4-5")

      assert {:ok, custo_caro} = AI.estimate_cost(caro, 1_000_000, 1_000_000)
      assert {:ok, custo_barato} = AI.estimate_cost(barato, 1_000_000, 1_000_000)

      assert custo_caro > custo_barato
      assert AI.provider() == global
    end
  end
end
