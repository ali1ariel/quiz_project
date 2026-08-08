defmodule QuizProject.Epub.Inline do
  @moduledoc """
  Converte a marcação inline do XHTML (negrito, itálico, código curto, link) em
  Markdown.

  O destino é o `MDEx` que o `QuizProjectWeb.Components.Markdown` já usa: assim
  o leitor herda a tipografia do `.qprose` que existe hoje, em vez de ganhar uma
  segunda pipeline de renderização só para o livro.
  """

  alias QuizProject.Epub.Html

  # Escapa só o que a marcação inline usa. `_` fica de fora de propósito: o
  # CommonMark não trata `_` no meio da palavra como ênfase, e escapá-lo encheria
  # de contrabarra identificadores como `train_images`, que neste livro aparecem
  # às centenas.
  @escape ~r/([\\*`\[\]])/

  @doc """
  Texto Markdown do conteúdo inline de um elemento Floki.

  `base_href` é o caminho do capítulo dentro do EPUB, usado para resolver links
  relativos; sem ele os `href` saem como vieram.
  """
  def to_markdown(nodes, base_href \\ nil) do
    nodes |> render(base_href) |> collapse_space()
  end

  @doc "Texto puro, sem marcação — usado onde Markdown não faz sentido."
  def to_text(nodes) do
    nodes |> Html.text() |> collapse_space()
  end

  # O colapso de espaço acontece só uma vez, no fim: aplicá-lo a cada nível da
  # recursão comeria o espaço entre elementos irmãos e grudaria "Figure 2.1" em
  # "MNIST sample digits".
  defp render(nodes, base_href) do
    nodes
    |> List.wrap()
    |> Enum.map_join("", &node_to_markdown(&1, base_href))
  end

  defp node_to_markdown(text, _base) when is_binary(text), do: text |> Html.restore() |> escape()

  defp node_to_markdown({tag, attrs, children}, base) do
    case tag do
      t when t in ~w(em i cite var) -> wrap("*", children, base)
      t when t in ~w(strong b) -> wrap("**", children, base)
      t when t in ~w(code kbd samp tt) -> code_span(children)
      "a" -> link(attrs, children, base)
      "br" -> "\n"
      "sup" -> "^" <> render(children, base)
      "sub" -> "~" <> render(children, base)
      # `img` inline fica fora da v1; o alt preserva o sentido da frase.
      "img" -> attrs |> attr("alt") |> to_string() |> escape()
      _ -> render(children, base)
    end
  end

  defp node_to_markdown({:comment, _}, _base), do: ""
  defp node_to_markdown(_other, _base), do: ""

  defp wrap(marker, children, base) do
    case render(children, base) do
      "" -> ""
      inner -> marker <> inner <> marker
    end
  end

  # Dentro de código a contrabarra não escapa nada, então o texto entra cru e a
  # cerca cresce até não colidir com as crases do próprio conteúdo.
  defp code_span(children) do
    case children |> Html.text() |> collapse_space() do
      "" ->
        ""

      text ->
        fence =
          ~r/`+/
          |> Regex.scan(text)
          |> Enum.map(fn [run] -> String.length(run) end)
          |> Enum.max(fn -> 0 end)
          |> then(&String.duplicate("`", &1 + 1))

        pad = if String.starts_with?(text, "`") or String.ends_with?(text, "`"), do: " ", else: ""
        fence <> pad <> text <> pad <> fence
    end
  end

  # Link para fora do livro vira link; referência interna
  # (`href="cap3.xhtml#nota12"`) vira só o texto.
  #
  # Transformá-la em âncora do próprio leitor é a v2. Até lá, gravar o caminho
  # dentro do EPUB produziria um `<a>` que aponta para um arquivo que não existe
  # na aplicação — um link morto na tela é pior que o texto sem link, e o alvo
  # volta na reingestão, que custa um upload.
  defp link(attrs, children, _base) do
    label = render(children, nil)

    case attr(attrs, "href") do
      href when is_binary(href) -> if external?(href), do: "[#{label}](#{href})", else: label
      nil -> label
    end
  end

  defp external?(href), do: String.contains?(href, "://") or String.starts_with?(href, "mailto:")

  defp attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp escape(text), do: Regex.replace(@escape, text, "\\\\\\1")

  # O XHTML da editora quebra linha e indenta dentro dos parágrafos; sem isto
  # cada parágrafo carregaria a indentação do arquivo para dentro do banco.
  defp collapse_space(text) do
    text
    |> String.replace(~r/[ \t\r\f\x{00A0}]*\n[ \t\r\f]*/u, " ")
    |> String.replace(~r/[ \t]{2,}/, " ")
    |> String.trim()
  end
end
