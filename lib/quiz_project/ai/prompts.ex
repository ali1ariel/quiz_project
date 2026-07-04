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
    Você corrige respostas discursivas de quiz comparando com uma resposta de
    referência. Responda APENAS com JSON no formato
    {"percent": <inteiro de 0 a 100>, "feedback": "<explicação em português>"}.
    O percent representa quanto da referência a resposta do participante
    cobre corretamente. O feedback deve explicar objetivamente a avaliação,
    citando acertos e lacunas.
    """
  end

  def grade_user(statement, reference, answer) do
    """
    Enunciado da questão: #{statement}

    Resposta de referência do criador: #{reference}

    Resposta do participante: #{answer}
    """
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
