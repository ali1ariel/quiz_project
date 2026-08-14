defmodule QuizProject.Epub.Block do
  @moduledoc """
  Unidade indivisível de conteúdo de um livro.

  O bloco é a espinha do sistema: o leitor renderiza blocos, a IA demarca
  blocos por referência e o filtro seleciona blocos por essa demarcação. Não
  existe conversão entre as visões porque não existem duas cópias do texto —
  reconstruir o livro é concatenar `content` na ordem de `position`.
  """

  @types ~w(paragraph heading code list_item quote table figure callout sidebar)a

  defstruct [
    :source_id,
    :position,
    :type,
    :lang,
    :caption,
    :content,
    :image_path,
    annotations: []
  ]

  @type t :: %__MODULE__{
          source_id: String.t() | nil,
          position: pos_integer() | nil,
          type: atom(),
          lang: String.t() | nil,
          caption: String.t() | nil,
          content: String.t(),
          image_path: String.t() | nil,
          annotations: [String.t()]
        }

  @doc "Tipos de bloco aceitos."
  def types, do: @types

  @doc """
  Nível de um bloco `:heading`, deduzido dos `#` do markdown.

  O nível mora no próprio conteúdo em vez de num campo à parte porque o bloco
  já é markdown e o `.qprose` renderiza a hierarquia sem ajuda.
  """
  def heading_level(%__MODULE__{type: :heading, content: content}) do
    case Regex.run(~r/\A(\#{1,6})\s/, content) do
      [_, hashes] -> String.length(hashes)
      nil -> 1
    end
  end

  def heading_level(%__MODULE__{}), do: nil

  @doc "Texto do título sem os `#` do markdown."
  def heading_text(%__MODULE__{type: :heading, content: content}) do
    content |> String.replace(~r/\A\#{1,6}\s*/, "") |> String.trim()
  end

  def heading_text(%__MODULE__{}), do: nil
end
