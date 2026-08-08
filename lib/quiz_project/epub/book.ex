defmodule QuizProject.Epub.Book do
  @moduledoc """
  Resultado da ingestão de um `.epub`: metadados, capítulos em ordem de leitura
  e a folha de estilo da editora já filtrada.
  """

  alias QuizProject.Epub.Chapter

  defstruct [
    :title,
    :author,
    :language,
    :identifier,
    :version,
    :css,
    chapters: []
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          author: String.t() | nil,
          language: String.t() | nil,
          identifier: String.t() | nil,
          version: String.t(),
          css: String.t() | nil,
          chapters: [Chapter.t()]
        }

  @doc "Total de blocos do livro."
  def block_count(%__MODULE__{chapters: chapters}),
    do: Enum.reduce(chapters, 0, &(length(&1.blocks) + &2))

  @doc """
  Texto corrido do livro inteiro, ou dos capítulos escolhidos.

  Reconstruir é concatenar blocos na ordem — é literalmente o original, não uma
  aproximação a verificar.
  """
  def to_text(%__MODULE__{chapters: chapters}), do: chapters_to_text(chapters)

  @doc "Texto corrido apenas dos capítulos de conteúdo, sem pré nem pós-textual."
  def body_text(%__MODULE__{chapters: chapters}),
    do: chapters |> Enum.filter(&(&1.kind == :body)) |> chapters_to_text()

  defp chapters_to_text(chapters) do
    chapters
    |> Enum.flat_map(& &1.blocks)
    |> Enum.map_join("\n\n", & &1.content)
  end
end
