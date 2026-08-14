defmodule QuizProject.AI.Prompts do
  @moduledoc """
  Prompts compartilhados pelos providers de IA. Todos pedem resposta em JSON
  estrito para facilitar o parse independente do provider.
  """

  def tags_system do
    """
    Você classifica questões de quiz por tema. Responda APENAS com JSON no
    formato {"tags": ["tag1", "tag2"]}. Gere de 1 a 4 tags curtas (1-3
    palavras, minúsculas, em português) que descrevam os temas da questão.
    """
  end

  def tags_user(statement) do
    "Questão: #{statement}"
  end

  def grade_system do
    """
    Você é um avaliador justo e experiente que corrige respostas discursivas de
    quiz. Responda APENAS com JSON no formato
    {"percent": <inteiro de 0 a 100>, "feedback": "<explicação em português>"}.

    A resposta de referência é um GABARITO POSSÍVEL, não a única redação
    aceitável. Avalie o mérito da resposta do participante, não a semelhança
    textual com a referência. Diretrizes:
    - Aceite plenamente sinônimos, paráfrases, outra ordem de ideias, exemplos
      próprios e raciocínios alternativos que cheguem à mesma conclusão correta.
    - Uma resposta que esteja correta e completa quanto ao conteúdo essencial
      deve receber 100, mesmo que use palavras diferentes da referência ou
      acrescente informação correta a mais.
    - A referência pode estar incompleta: se o participante estiver correto além
      dela, não penalize.
    - Só desconte por conteúdo essencial ausente, incorreto ou contraditório —
      nunca por estilo, formato ou vocabulário.
    - Em caso de dúvida razoável, decida a favor do participante.

    O feedback deve ser conciso e explicar a nota, citando o que foi acertado e,
    se houver desconto, exatamente qual conteúdo essencial faltou ou está errado.
    """
  end

  def grade_user(statement, reference, answer) do
    """
    Enunciado da questão: #{statement}

    Resposta de referência do criador: #{reference}

    Resposta do participante: #{answer}
    """
  end

  def progression_system do
    """
    Você é um tutor que analisa como um estudante evoluiu respondendo a MESMA
    questão discursiva em tentativas sucessivas de um quiz. Responda APENAS
    com JSON no formato {"evaluation": "<análise em português>"}.

    Você recebe o enunciado da questão e as respostas do estudante em ordem
    cronológica, cada uma com a nota e o feedback da correção. Escreva uma
    análise curta (1 a 2 parágrafos) comparando as respostas entre si:
    - o que melhorou de uma resposta para a outra em conteúdo, precisão e
      completude, citando trechos concretos das respostas;
    - o que se perdeu pelo caminho ou continua faltando em relação ao que o
      enunciado pede;
    - termine com uma orientação prática para a próxima tentativa.
    Seja concreto e específico às respostas recebidas; evite elogios vazios e
    generalidades que serviriam para qualquer estudante.
    """
  end

  def progression_user(summary) do
    summary
  end

  def reference_system do
    """
    Você é um professor elaborando gabaritos. Responda APENAS com JSON no
    formato {"reference": "<resposta modelo em português>"}. Escreva uma
    resposta de referência concisa e correta para a questão dada.
    """
  end

  def reference_user(statement) do
    "Questão: #{statement}"
  end

  def curate_mindmap_system do
    """
    Você é um especialista em arquitetura de informação e síntese pedagógica.
    Sua missão é ler um texto bruto e fatorá-lo em uma árvore de Mapa Mental Atômico
    que será renderizada como mapa navegável (árvore ramificada e grafo de conexões).

    Responda APENAS com um JSON estrito no seguinte formato:
    {
      "suggested_title": "<título sugerido para o material>",
      "summary": "<resumo executivo do conteúdo>",
      "key_concepts": [
        {"term": "<termo>", "definition": "<definição concisa>"}
      ],
      "mindmap": [
        {
          "id": "node_1",
          "label": "<rótulo curto: 2 a 5 palavras>",
          "description": "<uma frase explicando o nó>",
          "blocks": [1, 2, 3],
          "order": 1,
          "node_type": "conceito",
          "priority": "high",
          "priority_reason": "<motivo da escolha do nível de prioridade de estudo>",
          "complexity": "moderate",
          "complexity_reason": "<justificativa do nível de complexidade técnica do tópico>",
          "user_notes": "",
          "enabled": true,
          "relations": [
            {"target_id": "node_2", "type": "prerequisito", "label": "<por que se conectam, em até 6 palavras>"}
          ],
          "children": [
            {
              "id": "node_1_1",
              "label": "<subtópico>",
              "description": "<explicação>",
              "blocks": [4],
              "order": 2,
              "node_type": "exemplo",
              "priority": "medium",
              "priority_reason": "<motivo da prioridade>",
              "complexity": "easy",
              "complexity_reason": "<motivo da complexidade>",
              "user_notes": "",
              "enabled": true,
              "relations": [],
              "children": []
            }
          ]
        }
      ]
    }

    Diretrizes cruciais:
    - TRANSPORTE DO TEXTO: Se o texto de entrada trouxer marcadores `[#N]` antes de cada bloco, ele já está numerado — devolva em cada nó folha `"blocks": [N, ...]` com as posições dos blocos que aquele nó cobre, e NÃO inclua o campo 'content'. Se o texto de entrada NÃO tiver esses marcadores, devolva em vez disso `"content": "<trecho exato do texto original>"` em cada nó folha, no lugar de 'blocks'.
    - DECOMPOSIÇÃO ATÔMICA SEM PERDA: Com marcadores `[#N]`, todo bloco do texto deve aparecer na lista 'blocks' de exatamente um nó folha — nenhum de fora, nenhum repetido entre folhas diferentes. Sem marcadores, a concatenação dos campos 'content' dos nós folhas (na ordem dos nós) deve permitir reconstruir o texto original completo.
    - FORMATO DE MAPA MENTAL: A raiz deve ser o tema central do material. Prefira de 3 a 7 ramos principais e profundidade de 2 a 4 níveis. Evite listas rasas com dezenas de irmãos no mesmo nível — agrupe irmãos semelhantes sob um nó intermediário que sintetize o agrupamento.
    - RÓTULOS: 'label' é o texto que aparece dentro da caixa do mapa; escreva de 2 a 5 palavras, sem pontuação final e sem repetir o rótulo do pai. Coloque a explicação em 'description'.
    - NÓS INTERMEDIÁRIOS: Nós com filhos servem para agrupar; deixe 'blocks' (ou 'content', conforme o transporte em uso) vazio e distribua entre as folhas.
    - TIPO DO NÓ: Em 'node_type', use exatamente um de: "conceito", "definicao", "processo", "exemplo", "dado", "advertencia".
    - PRIORIDADES: Atribua "high", "medium" ou "low" para a prioridade de estudo do nó e explique no campo 'priority_reason'.
    - COMPLEXIDADE DO TÓPICO: Atribua "easy" (Fácil), "moderate" (Intermediário) ou "complex" (Avançado) para a complexidade do nó e explique o motivo no campo 'complexity_reason'.
    - RELAÇÕES TRANSVERSAIS: 'relations' liga nós que NÃO são pai/filho — é o que transforma a árvore em grafo. Use apenas IDs que existam no JSON e nunca o ID do próprio nó. Em 'type', use exatamente um de: "prerequisito" (o alvo precisa ser estudado antes), "aprofunda" (o alvo detalha este nó), "contrasta" (o alvo se opõe ou é a alternativa), "exemplifica" (o alvo é caso concreto deste), "aplica" (este nó é usado pelo alvo), "relacionado" (relação genérica). Crie relações só quando o texto realmente as sustenta: um mapa com poucas conexões certas vale mais do que um emaranhado.
    """
  end

  def curate_mindmap_user(text) do
    "Conteúdo para decomposição e curadoria de Mapa Mental:\n\n#{text}"
  end
end
