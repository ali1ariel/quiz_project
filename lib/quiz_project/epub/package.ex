defmodule QuizProject.Epub.Package do
  @moduledoc """
  Leitura do pacote: `META-INF/container.xml` aponta o `.opf`, e o `.opf` traz
  metadados, manifesto (todos os arquivos) e **spine** (a ordem de leitura).

  O spine é o que dispensa heurística de corte de capítulo: o EPUB declara a
  ordem, não a inferimos.
  """

  import SweetXml, only: [sigil_x: 2]

  defstruct [
    :root_path,
    :version,
    :title,
    :author,
    :language,
    :identifier,
    :toc_href,
    :nav_href,
    manifest: %{},
    spine: [],
    guide: %{}
  ]

  @container "META-INF/container.xml"

  @doc """
  Lê o pacote a partir do mapa `caminho => binário` do zip.

  Recusa antes de qualquer extração de texto: DRM e fixed-layout precisam ser
  detectados na ingestão, não descobertos na leitura.
  """
  def parse(files) when is_map(files) do
    with {:ok, opf_path} <- root_file(files),
         {:ok, opf} <- fetch(files, opf_path),
         package = %__MODULE__{} <- build(opf, opf_path),
         :ok <- check_drm(files, package),
         :ok <- check_layout(opf) do
      {:ok, package}
    end
  end

  @doc "Resolve um `href` do manifesto para o caminho dentro do zip."
  def resolve(%__MODULE__{root_path: root}, href) do
    href = href |> String.split("#") |> hd() |> URI.decode()

    case root do
      "" -> href
      dir -> dir |> Path.join(href) |> Path.expand("/") |> String.trim_leading("/")
    end
  end

  defp root_file(files) do
    case Map.fetch(files, @container) do
      {:ok, xml} ->
        case SweetXml.xpath(xml, ~x"//*[local-name()='rootfile']/@full-path"s) do
          "" -> {:error, :missing_opf}
          path -> {:ok, URI.decode(path)}
        end

      :error ->
        {:error, :not_an_epub}
    end
  end

  defp build(opf, opf_path) do
    root_path =
      case Path.dirname(opf_path) do
        "." -> ""
        dir -> dir
      end

    manifest =
      opf
      |> SweetXml.xpath(~x"//*[local-name()='manifest']/*[local-name()='item']"l,
        id: ~x"./@id"s,
        href: ~x"./@href"s,
        media_type: ~x"./@media-type"s,
        properties: ~x"./@properties"s
      )
      |> Map.new(&{&1.id, &1})

    %__MODULE__{
      root_path: root_path,
      version: SweetXml.xpath(opf, ~x"//*[local-name()='package']/@version"s),
      title: meta(opf, "title"),
      author: nil_if_blank(meta(opf, "creator")),
      language: nil_if_blank(meta(opf, "language")),
      identifier: nil_if_blank(meta(opf, "identifier")),
      manifest: manifest,
      spine: spine(opf),
      toc_href: toc_href(opf, manifest),
      nav_href: nav_href(manifest),
      guide: guide(opf)
    }
  end

  defp meta(opf, name) do
    opf
    |> SweetXml.xpath(~x"//*[local-name()='metadata']/*[local-name()='#{name}']/text()"s)
    |> String.trim()
  end

  # `linear="no"` marca conteúdo auxiliar que o leitor não percorre em sequência;
  # ele fica no livro, mas fora do fio principal.
  defp spine(opf) do
    opf
    |> SweetXml.xpath(~x"//*[local-name()='spine']/*[local-name()='itemref']"l,
      idref: ~x"./@idref"s,
      linear: ~x"./@linear"s
    )
    |> Enum.reject(&(&1.idref == ""))
  end

  # EPUB 2 aponta o NCX pelo atributo `toc` do spine; EPUB 3 usa `nav.xhtml`
  # declarado no manifesto. Os dois formatos convivem no mercado.
  defp toc_href(opf, manifest) do
    id = SweetXml.xpath(opf, ~x"//*[local-name()='spine']/@toc"s)

    case Map.get(manifest, id) do
      %{href: href} when href != "" ->
        href

      _ ->
        Enum.find_value(manifest, fn {_id, item} ->
          item.media_type == "application/x-dtbncx+xml" && item.href
        end)
    end
  end

  defp nav_href(manifest) do
    Enum.find_value(manifest, fn {_id, item} ->
      String.contains?(item.properties, "nav") && item.href
    end)
  end

  # O `<guide>` do EPUB 2 nomeia as partes do livro (`toc`, `copyright-page`,
  # `text`), e é a única fonte declarativa que separa pré-textual de capítulo.
  defp guide(opf) do
    opf
    |> SweetXml.xpath(~x"//*[local-name()='guide']/*[local-name()='reference']"l,
      type: ~x"./@type"s,
      href: ~x"./@href"s
    )
    |> Map.new(fn %{type: type, href: href} ->
      {href |> String.split("#") |> hd() |> URI.decode(), type}
    end)
  end

  # `encryption.xml` sozinho não é DRM: a ofuscação de fonte da própria
  # especificação usa o mesmo arquivo. Só é recusa quando o que está cifrado é
  # documento do spine — aí não há texto a extrair.
  defp check_drm(files, package) do
    documents =
      package.spine
      |> Enum.map(&Map.get(package.manifest, &1.idref))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new(&resolve(package, &1.href))

    encrypted =
      case Map.fetch(files, "META-INF/encryption.xml") do
        {:ok, xml} ->
          xml
          |> SweetXml.xpath(~x"//*[local-name()='CipherReference']/@URI"ls)
          |> MapSet.new(&URI.decode/1)

        :error ->
          MapSet.new()
      end

    cond do
      Map.has_key?(files, "META-INF/rights.xml") -> {:error, :drm_protected}
      not MapSet.disjoint?(encrypted, documents) -> {:error, :drm_protected}
      true -> :ok
    end
  end

  # Livro de layout fixo posiciona cada elemento por página; é outro problema,
  # não uma variação deste.
  defp check_layout(opf) do
    layout =
      opf
      |> SweetXml.xpath(~x"//*[local-name()='meta'][@property='rendition:layout']/text()"s)
      |> String.trim()

    legacy =
      opf
      |> SweetXml.xpath(~x"//*[local-name()='meta'][@name='fixed-layout']/@content"s)
      |> String.trim()

    if layout == "pre-paginated" or legacy in ~w(true True TRUE) do
      {:error, :fixed_layout}
    else
      :ok
    end
  end

  defp fetch(files, path) do
    case Map.fetch(files, path) do
      {:ok, content} -> {:ok, content}
      :error -> {:error, :missing_opf}
    end
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(value), do: value
end
