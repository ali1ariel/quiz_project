defmodule QuizProject.Epub.Chapter do
  @moduledoc """
  Um item do spine do EPUB, que é a ordem de leitura declarada pela editora.

  `kind` separa material de estudo do que só acompanha o livro. O spine não faz
  essa distinção — `titlepage`, `praise` e `copyright` aparecem no meio dos
  capítulos — e sem ela o leitor abriria no aviso de copyright.
  """

  defstruct [
    :source_id,
    :href,
    :title,
    :position,
    :level,
    kind: :body,
    blocks: []
  ]

  @type kind :: :front_matter | :body | :back_matter

  @type t :: %__MODULE__{
          source_id: String.t(),
          href: String.t(),
          title: String.t(),
          position: pos_integer(),
          level: pos_integer(),
          kind: kind(),
          blocks: [QuizProject.Epub.Block.t()]
        }
end
