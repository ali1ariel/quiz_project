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
end
