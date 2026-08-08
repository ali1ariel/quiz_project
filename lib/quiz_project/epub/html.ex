defmodule QuizProject.Epub.Html do
  @moduledoc """
  Parse do XHTML dos capítulos preservando o espaço em branco entre tags.

  O parser padrão do Floki (mochiweb) descarta nós de texto compostos só de
  espaço. Num livro cheio de `<span>` isso é destrutivo em dois lugares:
  `<span>Figure 2.1</span> <span>MNIST</span>` vira "Figure 2.1MNIST", e dentro
  de `<pre>` a indentação e as quebras de linha do código somem — 745 listagens
  chegariam ao leitor numa linha só.

  A solução é marcar esses espaços com caracteres da área de uso privado do
  Unicode antes de entregar o documento ao Floki, e desmarcá-los quando o texto
  sai da árvore. Trocar de parser resolveria também, mas custaria uma dependência
  nativa (`html5ever` ou `fast_html`) para um problema de dez linhas.
  """

  @sentinels %{
    " " => "\u{E001}",
    "\n" => "\u{E002}",
    "\t" => "\u{E003}",
    "\r" => "\u{E004}"
  }
  @restore Map.new(@sentinels, fn {char, sentinel} -> {sentinel, char} end)

  @doc "Nós do `<body>` do capítulo, com o espaço entre tags preservado."
  def parse_body(xhtml) when is_binary(xhtml) do
    case xhtml |> protect() |> Floki.parse_document() do
      {:ok, document} -> Floki.find(document, "body")
      {:error, _reason} -> []
    end
  end

  @doc "Texto de uma subárvore, já com o espaço original de volta."
  def text(nodes), do: nodes |> Floki.text() |> restore()

  @doc "Devolve o espaço em branco marcado por `parse_body/1`."
  def restore(text) when is_binary(text) do
    String.replace(text, Map.keys(@restore), &Map.fetch!(@restore, &1))
  end

  defp protect(xhtml) do
    Regex.replace(~r/>([ \t\r\n]+)</, xhtml, fn _match, whitespace ->
      ">" <> encode(whitespace) <> "<"
    end)
  end

  defp encode(whitespace) do
    String.replace(whitespace, Map.keys(@sentinels), &Map.fetch!(@sentinels, &1))
  end
end
