defmodule QuizProject.Epub.Blocks do
  @moduledoc """
  Converte o XHTML de um capítulo na sequência de blocos numerados.

  A varredura é em profundidade e para de descer assim que reconhece um bloco:
  um `p` dentro de `li` não vira parágrafo próprio porque o `li` já foi emitido,
  e o mesmo vale para `td` dentro de tabela e para a legenda dentro da listagem.
  """

  alias QuizProject.Epub.Block
  alias QuizProject.Epub.Html
  alias QuizProject.Epub.Inline

  @headings ~w(h1 h2 h3 h4 h5 h6)

  @doc """
  Blocos de um capítulo, numerados a partir de `start_position`.

  Devolve `{blocos, próxima_posição}` para o chamador encadear capítulos e
  manter `position` absoluta no livro.
  """
  def extract(xhtml, href, start_position \\ 1) when is_binary(xhtml) do
    blocks =
      xhtml
      |> Html.parse_body()
      |> Enum.flat_map(&walk(&1, href, nil))
      |> Enum.reject(&blank?/1)
      |> drop_repeated_source_ids()

    numbered =
      blocks
      |> Enum.with_index(start_position)
      |> Enum.map(fn {block, position} -> %{block | position: position} end)

    {numbered, start_position + length(numbered)}
  end

  # `inherited_id` carrega o id do ancestral mais próximo. A editora numera o
  # contêiner (`<div class="readable-text" id="p5">`), não o `<p>` de dentro, e
  # é esse id que a IA vai referenciar entre reingestões.
  defp walk(text, _href, _inherited_id) when is_binary(text), do: []
  defp walk({:comment, _}, _href, _inherited_id), do: []

  defp walk({tag, attrs, children} = node, href, inherited_id) do
    id = attr(attrs, "id") || inherited_id
    classes = classes(attrs)

    cond do
      tag in ~w(head script style) ->
        []

      code_container?(node, classes) ->
        [code_block(node, id)]

      tag == "pre" ->
        [
          %Block{
            source_id: id,
            type: :code,
            content: trim_code(Html.text(children)),
            lang: lang(attrs)
          }
        ]

      tag == "table" ->
        [table_block(node, id, nil, href)]

      table_container?(classes) ->
        [table_container_block(node, id, href)]

      figure_container?(tag, classes) ->
        [figure_block(node, id, href)]

      sidebar?(classes) ->
        [sidebar_block(node, id, href)]

      callout?(classes) ->
        [%Block{source_id: id, type: :callout, content: Inline.to_markdown(children, href)}]

      tag in @headings ->
        [heading_block(tag, children, id, href)]

      tag == "li" ->
        [%Block{source_id: id, type: :list_item, content: Inline.to_markdown(children, href)}]

      tag == "blockquote" ->
        [%Block{source_id: id, type: :quote, content: Inline.to_markdown(children, href)}]

      tag == "p" ->
        [%Block{source_id: id, type: :paragraph, content: Inline.to_markdown(children, href)}]

      true ->
        Enum.flat_map(children, &walk(&1, href, id))
    end
  end

  defp walk(_other, _href, _inherited_id), do: []

  # Reconhecimento de contêineres

  # Listagem de código: um contêiner que embrulha `<pre>` junto com o título e
  # as anotações numeradas. Reconhecido pela presença do `<pre>`, não pela
  # classe, para valer em EPUBs de outras editoras.
  defp code_container?({tag, _attrs, _children} = node, _classes) do
    tag in ~w(div section figure aside) and Floki.find(node, "pre") != []
  end

  defp table_container?(classes), do: role?(classes, "table-container")

  defp figure_container?(tag, classes),
    do: tag in ~w(figure img) or role?(classes, "figure-container")

  defp callout?(classes), do: role?(classes, "callout") or role?(classes, "callout-container")

  defp sidebar?(classes), do: role?(classes, "sidebar") or role?(classes, "sidebar-container")

  # Construção de cada tipo

  defp heading_block(tag, children, id, href) do
    level = tag |> String.trim_leading("h") |> String.to_integer()
    text = Inline.to_markdown(children, href)
    %Block{source_id: id, type: :heading, content: String.duplicate("#", level) <> " " <> text}
  end

  # Os ~2.000 `span` de coloração dentro do `<pre>` não pintam nada: as classes
  # (`_Code-Blue--Light-`, `_Code-Gray`) não têm regra na folha de estilo do
  # livro, são resíduo do InDesign da edição impressa. `Floki.text/1` os descarta
  # e o realce por linguagem fica com o cliente.
  defp code_block(node, id) do
    pre = node |> Floki.find("pre") |> List.first()

    %Block{
      source_id: id,
      type: :code,
      caption: caption(node),
      lang: pre |> pre_attrs() |> lang(),
      content: pre |> Floki.children() |> Html.text() |> trim_code(),
      annotations: annotations(node)
    }
  end

  # As anotações numeradas ("#1 Equivalent to the previous example") são
  # conteúdo, não decoração: explicam as marcas que ficam dentro do código.
  defp annotations(node) do
    node
    |> Floki.find("[class*=code-annotations]")
    |> Enum.flat_map(fn overlay ->
      overlay
      |> Floki.children()
      |> Enum.map_join("", fn
        {"br", _, _} -> "\n"
        other -> Html.text([other])
      end)
      |> String.split("\n")
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp table_container_block(node, id, href) do
    case Floki.find(node, "table") do
      [table | _] -> table_block(table, id, caption(node), href)
      [] -> %Block{source_id: id, type: :table, content: Inline.to_markdown(node, href)}
    end
  end

  defp table_block(table, id, caption, href) do
    if code_table?(table) do
      code_table_block(table, id, caption)
    else
      data_table_block(table, id, caption, href)
    end
  end

  # Editora que numera linha de código costuma diagramar a listagem como tabela:
  # uma linha de tabela por linha de código, com a primeira célula servindo de
  # medianiz para o número. Não há `<pre>` em lugar nenhum.
  #
  # Duas condições, e as duas importam. A classe com "code" é o que a editora
  # declarou; a ausência de `<th>` é o que separa isso de tabela de dados de
  # verdade, que nestes livros sempre traz cabeçalho.
  defp code_table?({"table", attrs, _children} = table) do
    Floki.find(table, "th") == [] and
      (code_class?(classes(attrs)) or
         table |> Floki.find("td") |> Enum.any?(&code_class?(classes(elem(&1, 1)))))
  end

  defp code_table?(_node), do: false

  defp code_class?(classes), do: Enum.any?(classes, &String.contains?(&1, "code"))

  defp code_table_block(table, id, caption) do
    content =
      table
      |> Floki.find("tr")
      |> Enum.map_join("\n", &code_row/1)
      |> trim_code()

    %Block{source_id: id, type: :code, caption: caption, content: content}
  end

  # A medianiz do número de linha não é conteúdo. Quando a editora marca qual
  # célula é o código, seguimos a marcação; quando não marca, a última célula da
  # linha é o código e as anteriores são a medianiz.
  defp code_row(row) do
    cells = Floki.find(row, "td, th")

    case Enum.filter(cells, &code_line_cell?/1) do
      [] -> cells |> List.last() |> cell_text()
      marked -> Enum.map_join(marked, "", &cell_text/1)
    end
  end

  defp code_line_cell?({_tag, attrs, _children}) do
    attrs |> classes() |> Enum.any?(&String.contains?(&1, "codeline"))
  end

  defp cell_text(nil), do: ""
  defp cell_text(cell), do: cell |> Floki.children() |> Html.text()

  defp data_table_block(table, id, caption, href) do
    rows =
      table
      |> Floki.find("tr")
      |> Enum.map(fn row ->
        row
        |> Floki.find("th, td")
        |> Enum.map(&(&1 |> Floki.children() |> Inline.to_markdown(href) |> escape_pipes()))
      end)

    %Block{
      source_id: id,
      type: :table,
      caption: caption,
      content: markdown_table(rows)
    }
  end

  # Tabela em GFM: a primeira linha vira cabeçalho, que é o que o formato exige
  # mesmo quando o EPUB não traz `thead`.
  defp markdown_table([]), do: ""

  defp markdown_table([header | body]) do
    width = Enum.reduce([header | body], 0, &max(length(&1), &2))
    separator = List.duplicate("---", width)

    [pad(header, width), separator | Enum.map(body, &pad(&1, width))]
    |> Enum.map_join("\n", &("| " <> Enum.join(&1, " | ") <> " |"))
  end

  defp pad(row, width), do: row ++ List.duplicate("", width - length(row))

  defp escape_pipes(cell), do: String.replace(cell, "|", "\\|")

  # Imagens ficam fora da v1, mas o bloco `:figure` já existe para que a v2 não
  # precise de migração: legenda e texto alternativo sobrevivem à ingestão.
  defp figure_block(node, id, href) do
    images = Floki.find(node, "img")
    alt = images |> Floki.attribute("alt") |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
    caption = caption(node)

    source =
      images
      |> Floki.attribute("src")
      |> List.first()
      |> case do
        nil -> nil
        src -> Inline.resolve_path(src, href)
      end

    %Block{
      source_id: id,
      type: :figure,
      caption: caption,
      content: caption || alt,
      image_path: source,
      annotations: if(alt == "", do: [], else: [alt])
    }
  end

  # A barra lateral vira um bloco único, ao contrário do resto: os `id` de
  # dentro dela se perdem, mas ela é uma digressão fechada e quebrá-la em
  # parágrafos soltos jogaria o leitor para fora do fio do capítulo.
  defp sidebar_block(node, id, href) do
    content =
      node
      |> Floki.children()
      |> Enum.flat_map(&walk(&1, href, nil))
      |> Enum.reject(&blank?/1)
      |> Enum.map_join("\n\n", & &1.content)

    %Block{source_id: id, type: :sidebar, content: content}
  end

  defp caption(node) do
    node
    |> Floki.find("h1, h2, h3, h4, h5, h6, caption, figcaption")
    |> List.first()
    |> case do
      nil -> nil
      heading -> heading |> Floki.children() |> Inline.to_text()
    end
    |> then(fn
      "" -> nil
      other -> other
    end)
  end

  defp pre_attrs({_tag, attrs, _children}), do: attrs
  defp pre_attrs(_), do: []

  # A linguagem não é declarada na marcação deste livro; quando a editora
  # informa, é por convenção de classe (`language-python`) ou por atributo.
  defp lang(attrs) do
    class = attr(attrs, "class") || ""

    cond do
      value = attr(attrs, "data-lang") ->
        value

      match = Regex.run(~r/\b(?:language|lang|brush:?)[-\s]([a-z0-9+#]+)/i, class) ->
        Enum.at(match, 1)

      true ->
        nil
    end
  end

  defp trim_code(text) do
    text
    # O realce da editora separa cada trecho colorido com espaço de largura
    # zero. Invisível na tela, mas ele entra na busca e vai junto no copiar.
    |> String.replace("\u{200B}", "")
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/\A\n+/, "")
    |> String.replace(~r/[ \t\n]+\z/, "")
  end

  defp attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp classes(attrs), do: attrs |> attr("class") |> to_string() |> String.split()

  # O papel tem que casar com a classe inteira ou com o sufixo dela. Casar por
  # substring confundia `callout-container-h5` — o título dentro da caixa — com a
  # própria caixa, e o título saía do capítulo como se fosse um aviso.
  defp role?(classes, role) do
    Enum.any?(classes, &(&1 == role or String.ends_with?(&1, "-" <> role)))
  end

  defp blank?(%Block{type: :figure}), do: false
  defp blank?(%Block{content: content}), do: String.trim(to_string(content)) == ""

  # O id do contêiner é herdado por todos os blocos que descem dele, então um
  # `div id="p5"` com dois parágrafos produziria dois blocos com a mesma chave.
  # Só o primeiro fica com o id; a chave `(capítulo, source_id)` continua única e
  # os demais se localizam por `position`.
  defp drop_repeated_source_ids(blocks) do
    {reversed, _seen} =
      Enum.reduce(blocks, {[], MapSet.new()}, fn block, {acc, seen} ->
        cond do
          is_nil(block.source_id) -> {[block | acc], seen}
          MapSet.member?(seen, block.source_id) -> {[%{block | source_id: nil} | acc], seen}
          true -> {[block | acc], MapSet.put(seen, block.source_id)}
        end
      end)

    Enum.reverse(reversed)
  end
end
