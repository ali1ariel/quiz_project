defmodule QuizProject.AI do
  @moduledoc """
  Fachada da camada de IA. A regra de negócio chama estas funções e nunca um
  provider diretamente. O provider é escolhido em tempo de execução via
  configuração (`:quiz_project, :ai_provider`), alimentada por variáveis de
  ambiente no `runtime.exs`.
  """

  @doc "Gera até 4 tags internas para uma questão. Nunca levanta exceção."
  def generate_tags(statement) when is_binary(statement) do
    case provider().generate_tags(statement) do
      {:ok, tags} when is_list(tags) -> {:ok, Enum.take(tags, 4)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Corrige resposta discursiva contra a referência do criador (ou gerada).
  Retorna `{:ok, %{percent: 0..100, feedback: texto}}`.
  """
  def grade_text_answer(statement, reference, answer) do
    with {:ok, %{percent: percent, feedback: feedback}} <-
           provider().grade_text_answer(statement, reference, answer) do
      {:ok, %{percent: percent |> max(0) |> min(100), feedback: feedback}}
    end
  end

  @doc "Gera resposta de referência quando o criador não forneceu nenhuma."
  def generate_reference(statement) do
    provider().generate_reference(statement)
  end

  @doc """
  Avalia a evolução do participante respondendo a mesma questão discursiva
  em tentativas sucessivas, a partir de um resumo textual do histórico.
  Retorna `{:ok, texto}`.
  """
  def evaluate_progression(summary) when is_binary(summary) do
    provider().evaluate_progression(summary)
  end

  @doc """
  Decompõe o texto em Mapa Mental Atômico.

  Sem `opts`, usa o provedor e o modelo configurados globalmente — é assim que
  todo o resto do sistema chama. `:provider` e `:model` existem para a curadoria
  de capítulo de livro, onde quem clica escolhe na hora; a escolha vale só para
  aquela chamada e não altera a configuração de ninguém.
  """
  def curate_mindmap(text, opts \\ []) when is_binary(text) do
    provider = Keyword.get(opts, :provider) || provider()
    provider.curate_mindmap(text, opts)
  end

  @doc "Retorna o módulo do provedor de IA atualmente configurado."
  def provider do
    Application.get_env(:quiz_project, :ai_provider, QuizProject.AI.Fake)
  end

  @doc """
  Retorna uma descrição amigável do provedor e modelo de IA em uso. Útil para inspeção no IEx.
  """
  def current_provider do
    case runtime_info() do
      %{provider: name, model: nil} -> name
      %{provider: name, model: model} -> "#{name} (modelo: #{model})"
    end
  end

  # Provedores que a interface pode oferecer. A chave em texto é o que trafega
  # pelo formulário: nunca se converte string de navegador em átomo de módulo,
  # que é como se transforma um `<select>` em execução de código arbitrário.
  @providers [
    %{
      slug: "claude",
      name: "Claude",
      module: QuizProject.AI.Claude,
      api_key: :anthropic_api_key,
      model_key: :anthropic_model
    },
    %{
      slug: "openai",
      name: "OpenAI",
      module: QuizProject.AI.OpenAI,
      api_key: :openai_api_key,
      model_key: :openai_model
    },
    %{
      slug: "gemini",
      name: "Gemini",
      module: QuizProject.AI.Gemini,
      api_key: :gemini_api_key,
      model_key: :gemini_model
    },
    %{
      slug: "fake",
      name: "Fake (heurística local sem IA externa)",
      module: QuizProject.AI.Fake,
      api_key: nil,
      model_key: nil
    }
  ]

  # Preço em dólares por milhão de tokens e janela de entrada em tokens, dos
  # três provedores configuráveis. Conferido em 2026-08-09 na documentação de
  # cada fabricante — não de memória, que envelhece sem avisar. `context: nil`
  # quer dizer que a fonte não publica o número, e a interface mostra isso como
  # desconhecido em vez de inventar.
  #
  # O critério de entrada é cobertura, não histórico: para cada provedor, a
  # versão atual de cada faixa de capacidade que ele oferece. É o que a tela de
  # escolha precisa — poder subir quando o capítulo é difícil e descer quando é
  # simples, dentro do mesmo provedor — e é decidível sem opinião, ao contrário
  # de "os mais relevantes".
  #
  # Versão antiga não fica só por ser conhecida. Quem tiver uma fixada por
  # variável de ambiente continua sendo atendido; ela só aparece como "sem preço
  # tabelado".
  #
  # `tier` é julgamento nosso, não número de fabricante, e serve só para avisar
  # na interface: `:light` é a faixa econômica (mini, nano, lite, flash-lite,
  # haiku), que costuma não dar conta de decompor um capítulo inteiro sem perda
  # — e falhar depois de gastar é o pior dos resultados.
  #
  # Duas escolhas deliberadas de arredondamento, ambas para cima:
  #
  #   - Sonnet 5 está com promoção ($2/$10) até 2026-08-31; a tabela guarda o
  #     preço cheio, para a estimativa não encolher sozinha na virada do mês.
  #   - Gemini 2.5/3.1 Pro cobram por faixa de tamanho do prompt. Fica a faixa
  #     baixa, que é a que vale para capítulo de livro (abaixo de 200k tokens).
  @models %{
    # Anthropic — platform.claude.com/docs/en/about-claude/models/overview
    "claude-fable-5" => %{
      p: "claude",
      input: 10.0,
      output: 50.0,
      context: 1_000_000,
      tier: :frontier
    },
    "claude-opus-5" => %{
      p: "claude",
      input: 5.0,
      output: 25.0,
      context: 1_000_000,
      tier: :flagship
    },
    "claude-sonnet-5" => %{
      p: "claude",
      input: 3.0,
      output: 15.0,
      context: 1_000_000,
      tier: :balanced
    },
    "claude-haiku-4-5" => %{p: "claude", input: 1.0, output: 5.0, context: 200_000, tier: :light},

    # OpenAI — developers.openai.com/api/docs/pricing. A linha 5.6 não tem
    # variante "pro"; a de raciocínio mais forte continua sendo a 5.5.
    "gpt-5.5-pro" => %{p: "openai", input: 30.0, output: 180.0, context: 272_000, tier: :frontier},
    "gpt-5.6-sol" => %{p: "openai", input: 5.0, output: 30.0, context: nil, tier: :flagship},
    "gpt-5.6-terra" => %{p: "openai", input: 2.0, output: 12.0, context: nil, tier: :balanced},
    "gpt-5.6-luna" => %{p: "openai", input: 0.2, output: 1.2, context: nil, tier: :light},

    # Google — ai.google.dev/gemini-api/docs/pricing (a página não publica a
    # janela de contexto, e a de modelos também não; por isso todas nil). Não há
    # Pro nas linhas 3.5/3.6, então o topo do Gemini é o Pro da 3.1.
    "gemini-3.1-pro-preview" => %{
      p: "gemini",
      input: 2.0,
      output: 12.0,
      context: nil,
      tier: :flagship
    },
    "gemini-3.6-flash" => %{p: "gemini", input: 1.5, output: 7.5, context: nil, tier: :balanced},
    "gemini-3.5-flash-lite" => %{p: "gemini", input: 0.3, output: 2.5, context: nil, tier: :light}
  }

  @doc """
  Provedor e modelo em uso, em forma estruturada. `pricing` vem em dólares por
  milhão de tokens e `context` é a janela de entrada; ambos são `nil` quando o
  modelo não está na tabela — desconhecido aparece como desconhecido, nunca
  como zero.
  """
  def runtime_info do
    slug = slug_for(provider())
    describe(slug, slug && model_for(slug))
  end

  @doc """
  Provedor e modelo pré-selecionados no formulário de escolha: os globais,
  quando dão para processar; senão o primeiro provedor com chave configurada.
  A tela nunca abre já apontando para algo que não roda.
  """
  def default_selection do
    atual = slug_for(provider())

    slug =
      if atual && available?(atual),
        do: atual,
        else: Enum.find(providers(), &available?(&1.slug)).slug

    %{provider: slug, model: model_for(slug)}
  end

  @doc "Provedores oferecidos na escolha, com disponibilidade e modelos."
  def catalog do
    Enum.map(providers(), fn provider ->
      provider
      |> Map.take([:slug, :name])
      |> Map.put(:available?, available?(provider.slug))
      |> Map.put(:models, models_of(provider.slug))
    end)
  end

  @doc """
  Indica se o provedor tem chave de API configurada — ou seja, se adianta
  apertar o botão. O Fake não usa chave e está sempre disponível.
  """
  def available?(slug) do
    case find_provider(slug) do
      %{api_key: nil} -> true
      %{api_key: chave} -> Application.get_env(:quiz_project, chave) not in [nil, ""]
      nil -> false
    end
  end

  @doc """
  Valida uma escolha vinda do formulário e devolve o que é preciso para chamar
  e para mostrar. Rejeita provedor desconhecido, modelo desconhecido e modelo
  que não pertence ao provedor escolhido — a tela é sugestão, não autorização.
  """
  def resolve(slug, model) do
    with %{module: modulo} = provider <- find_provider(slug),
         true <- model == nil or match?(%{p: ^slug}, Map.get(@models, model)) do
      {:ok,
       Map.merge(describe(slug, model || model_for(slug)), %{module: modulo, name: provider.name})}
    else
      nil -> {:error, :unknown_provider}
      false -> {:error, :unknown_model}
    end
  end

  defp providers, do: @providers

  defp find_provider(slug), do: Enum.find(@providers, &(&1.slug == slug))

  defp slug_for(modulo) do
    case Enum.find(@providers, &(&1.module == modulo)) do
      %{slug: slug} -> slug
      nil -> nil
    end
  end

  defp model_for(slug) do
    case find_provider(slug) do
      %{model_key: nil} -> nil
      %{model_key: chave} -> Application.get_env(:quiz_project, chave)
      nil -> nil
    end
  end

  # Mais capaz primeiro: quem abre a lista para escolher deve tropeçar no que
  # dá conta do trabalho antes de tropeçar no que é barato.
  #
  # `:frontier` é o topo de preço premium (Fable 5, GPT-5.5 Pro), separado de
  # `:flagship` porque a diferença de custo entre os dois é de 2x a 6x — juntá-los
  # numa faixa só esconderia justamente o que a tela existe para mostrar.
  @tier_order %{frontier: 0, flagship: 1, balanced: 2, light: 3}

  defp models_of(slug) do
    @models
    |> Enum.filter(fn {_id, entrada} -> entrada.p == slug end)
    |> Enum.map(fn {id, entrada} -> entrada |> Map.delete(:p) |> Map.put(:id, id) end)
    |> Enum.sort_by(&{Map.fetch!(@tier_order, &1.tier), &1.id})
  end

  defp describe(slug, model) do
    entrada = Map.get(@models, model)

    nome =
      case find_provider(slug) do
        %{name: nome} -> nome
        nil -> inspect(provider())
      end

    %{
      slug: slug,
      provider: nome,
      model: model,
      pricing: entrada && Map.take(entrada, [:input, :output]),
      context: entrada && entrada.context,
      tier: entrada && entrada.tier,
      available?: slug != nil and available?(slug)
    }
  end

  @doc """
  Custo em dólares de uma chamada com os tokens informados, ou `:unknown`
  quando não há preço tabelado para o modelo em uso.
  """
  def estimate_cost(input_tokens, output_tokens) do
    estimate_cost(runtime_info(), input_tokens, output_tokens)
  end

  @doc """
  Mesmo cálculo para uma seleção qualquer — é o que permite comparar preço
  entre provedores antes de escolher, sem trocar a configuração global.
  """
  def estimate_cost(%{pricing: %{input: entrada, output: saida}}, input_tokens, output_tokens) do
    {:ok, input_tokens / 1_000_000 * entrada + output_tokens / 1_000_000 * saida}
  end

  def estimate_cost(_info, _input_tokens, _output_tokens), do: :unknown
end
