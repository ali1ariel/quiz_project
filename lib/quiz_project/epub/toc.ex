defmodule QuizProject.Epub.Toc do
  @moduledoc """
  Sumário do livro: `toc.ncx` no EPUB 2, `nav.xhtml` no EPUB 3.

  O spine dá a ordem de leitura; o sumário dá hierarquia e títulos. Os dois são
  necessários — um sumário de 350 entradas em 4 níveis descreve um spine de 31
  itens, e nenhum dos dois substitui o outro.
  """

  import SweetXml, only: [sigil_x: 2]

  @type entry :: %{href: String.t(), title: String.t(), level: pos_integer(), class: String.t()}

  @doc """
  Título e nível de cada documento, indexados pelo `href` sem fragmento.

  Entradas mais profundas do mesmo arquivo (seções dentro do capítulo) são
  ignoradas: quem manda no título do capítulo é a primeira ocorrência.
  """
  def index(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      Map.put_new(acc, entry.href, entry)
    end)
  end

  @doc "Entradas do `toc.ncx` (EPUB 2), em ordem de leitura."
  @spec parse_ncx(binary()) :: [entry()]
  def parse_ncx(xml) do
    xml
    |> SweetXml.xpath(~x"//*[local-name()='navMap']/*[local-name()='navPoint']"l)
    |> Enum.flat_map(&nav_point(&1, 1))
  end

  defp nav_point(node, level) do
    src = SweetXml.xpath(node, ~x"./*[local-name()='content']/@src"s)

    entry = %{
      href: src |> String.split("#") |> hd() |> URI.decode(),
      title: node |> SweetXml.xpath(~x"./*[local-name()='navLabel']//text()"s) |> squish(),
      level: level,
      class: SweetXml.xpath(node, ~x"./@class"s)
    }

    children =
      node
      |> SweetXml.xpath(~x"./*[local-name()='navPoint']"l)
      |> Enum.flat_map(&nav_point(&1, level + 1))

    if entry.href == "", do: children, else: [entry | children]
  end

  @doc "Entradas do `nav.xhtml` (EPUB 3), em ordem de leitura."
  @spec parse_nav(binary()) :: [entry()]
  def parse_nav(xhtml) do
    case Floki.parse_document(xhtml) do
      {:ok, document} ->
        document
        |> Floki.find("nav[epub|type=toc], nav[*|type=toc], nav")
        |> List.first()
        |> case do
          nil -> []
          nav -> nav |> Floki.find("ol") |> List.first() |> list_items(1)
        end

      {:error, _} ->
        []
    end
  end

  defp list_items(nil, _level), do: []

  defp list_items(list, level) do
    list
    |> Floki.children()
    |> Enum.filter(&match?({"li", _, _}, &1))
    |> Enum.flat_map(fn item ->
      anchor = item |> Floki.find("a, span") |> List.first()

      entry =
        case anchor do
          nil ->
            []

          node ->
            href = node |> Floki.attribute("href") |> List.first() |> to_string()

            [
              %{
                href: href |> String.split("#") |> hd() |> URI.decode(),
                title: node |> Floki.text() |> squish(),
                level: level,
                class: ""
              }
            ]
        end

      nested =
        item
        |> Floki.children()
        |> Enum.filter(&match?({"ol", _, _}, &1))
        |> Enum.flat_map(&list_items(&1, level + 1))

      Enum.reject(entry, &(&1.href == "")) ++ nested
    end)
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
end
