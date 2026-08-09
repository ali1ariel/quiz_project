defmodule QuizProject.Epub do
  @moduledoc """
  Ingestão de `.epub`: entra o binário, saem capítulos e blocos numerados.

  Pipeline determinística, sem IA em nenhuma etapa:

      .epub (zip)
        └─ META-INF/container.xml   → caminho do .opf
             └─ .opf
                  ├─ manifest        → todos os arquivos do pacote
                  └─ spine           → ORDEM DE LEITURA (a fonte dos capítulos)
             └─ nav.xhtml (EPUB 3)   → títulos
                ou toc.ncx (EPUB 2)
        └─ um XHTML por capítulo → blocos numerados

  Função pura: não toca banco nem disco. Quem persiste é
  `QuizProject.AdaptiveStudy.Books`.
  """

  alias QuizProject.Epub.Block
  alias QuizProject.Epub.Blocks
  alias QuizProject.Epub.Book
  alias QuizProject.Epub.Chapter
  alias QuizProject.Epub.Css
  alias QuizProject.Epub.Package
  alias QuizProject.Epub.Toc

  @type error ::
          :not_an_epub
          | :corrupt_archive
          | :missing_opf
          | :drm_protected
          | :fixed_layout
          | :no_readable_content

  @doc """
  Lê o livro inteiro. `on_chapter` recebe `{índice, total, título}` a cada
  capítulo processado, que é como a ingestão reporta progresso.
  """
  @spec parse(binary(), keyword()) :: {:ok, Book.t()} | {:error, error()}
  def parse(binary, opts \\ []) when is_binary(binary) do
    on_chapter = Keyword.get(opts, :on_chapter, fn _ -> :ok end)

    with {:ok, files} <- unzip(binary),
         {:ok, package} <- Package.parse(files) do
      build(files, package, on_chapter)
    end
  end

  @doc """
  Verificação barata, feita ainda no request do upload.

  A ingestão completa é assíncrona, mas DRM e fixed-layout precisam de recusa
  imediata na tela: são condições do pacote, não do conteúdo, e esperar o
  processamento para dizer "não abro este arquivo" é ruim de propósito nenhum.
  """
  @spec inspect_package(binary()) :: {:ok, map()} | {:error, error()}
  def inspect_package(binary) when is_binary(binary) do
    with {:ok, files} <- unzip(binary),
         {:ok, package} <- Package.parse(files) do
      {:ok,
       %{
         title: package.title,
         author: package.author,
         version: package.version,
         chapter_count: length(package.spine)
       }}
    end
  end

  @doc "Mensagem de recusa em português, para a tela de upload."
  def error_message(:not_an_epub), do: "O arquivo não é um EPUB válido."
  def error_message(:corrupt_archive), do: "O arquivo EPUB está corrompido e não pôde ser aberto."
  def error_message(:missing_opf), do: "O EPUB não declara um pacote de conteúdo legível."

  def error_message(:drm_protected),
    do: "Este EPUB está protegido por DRM e não pode ser aberto. Use uma cópia sem proteção."

  def error_message(:fixed_layout),
    do:
      "Este EPUB é de layout fixo (quadrinhos ou livro ilustrado), formato ainda não suportado pelo leitor."

  def error_message(:no_readable_content),
    do: "Não foi possível extrair texto deste EPUB."

  def error_message(_), do: "Não foi possível processar este EPUB."

  defp unzip(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, entries} ->
        {:ok, Map.new(entries, fn {name, content} -> {to_string(name), content} end)}

      {:error, _reason} ->
        {:error, :corrupt_archive}
    end
  end

  defp build(files, package, on_chapter) do
    toc = toc_index(files, package)
    total = length(package.spine)

    {chapters, _position, _index} =
      Enum.reduce(package.spine, {[], 1, 1}, fn item, {acc, position, index} ->
        {chapter, next_position} = chapter(files, package, toc, item, index, position)
        on_chapter.({index, total, chapter.title})
        {[chapter | acc], next_position, index + 1}
      end)

    chapters =
      chapters |> Enum.reverse() |> Enum.reject(&(&1.blocks == [] or toc_page?(&1)))

    images = images(files, chapters)

    if chapters == [] do
      {:error, :no_readable_content}
    else
      {:ok,
       %Book{
         images: images,
         title: title(package),
         author: package.author,
         language: package.language,
         identifier: package.identifier,
         version: if(package.version == "", do: "2.0", else: package.version),
         css: stylesheet(files, package),
         chapters: chapters |> prune_missing_images(images) |> renumber()
       }}
    end
  end

  defp chapter(files, package, toc, item, index, position) do
    manifest_item = Map.get(package.manifest, item.idref, %{href: "", media_type: ""})
    path = Package.resolve(package, manifest_item.href)
    entry = Map.get(toc, manifest_item.href) || Map.get(toc, path)

    {blocks, next_position} =
      case Map.fetch(files, path) do
        {:ok, xhtml} -> Blocks.extract(xhtml, path, position)
        :error -> {[], position}
      end

    chapter = %Chapter{
      source_id: item.idref,
      href: manifest_item.href,
      title: chapter_title(entry, blocks, item.idref),
      position: index,
      level: (entry && entry.level) || 1,
      kind: kind(item, manifest_item, package, entry),
      blocks: blocks
    }

    {chapter, next_position}
  end

  # O sumário é a melhor fonte de título; sem ele, o primeiro cabeçalho do
  # próprio capítulo; sem nenhum dos dois, o id do spine, que ao menos é único.
  defp chapter_title(entry, blocks, idref) do
    heading = Enum.find(blocks, &(&1.type == :heading))

    cond do
      entry && entry.title != "" -> entry.title
      heading -> Block.heading_text(heading)
      true -> humanize(idref)
    end
  end

  defp humanize(idref) do
    idref |> String.replace(~r/[-_]+/, " ") |> String.trim() |> :string.titlecase()
  end

  # Página de sumário impresso do próprio livro (o "Text/contents.html" ou
  # "Table of Contents" que a editora inclui como página de leitura, além do
  # nav/NCX que já dá a hierarquia). Sai do livro em vez de virar capítulo:
  # duplica o que o sumário do leitor já mostra corretamente (`chapter.level`
  # até o fundo), e como página impressa genérica ela não carrega marcação de
  # link, recuo ou quebra de linha que sobreviva à extração de blocos — vira
  # texto corrido ou marcador gigante em vez de navegação de verdade.
  #
  # Não é a mesma lista de `@front_matter`: aquela também pega "praise",
  # "copyright", "preface" — página de leitura legítima, não redundante com
  # nada. Aqui só entra o que É, de fato, o sumário.
  @toc_titles ~w(contents table_of_contents sumario)

  defp toc_page?(%Chapter{title: title}) do
    normalized =
      title
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/\s+/, "_")
      |> String.trim()

    normalized in @toc_titles
  end

  # O spine traz `titlepage`, `praise` e `copyright` misturados aos capítulos e
  # nada nele os distingue. Sem critério, o leitor abre no aviso de copyright e
  # a IA processa a página de agradecimentos.
  #
  # A ordem das fontes é da mais declarativa para a mais suposta: o `<guide>` do
  # OPF nomeia as partes, o `linear="no"` marca o que sai do fio principal, e só
  # então entra o nome do arquivo.
  @front_matter ~w(
    cover titlepage title title-page halftitle half-title frontmatter front-matter
    praise copyright copyright-page contents toc nav dedication epigraph
    foreword preface acknowledgment acknowledgments acknowledgements
    about-this-book about-the-author about-the-authors about-the-cover
    about-the-cover-illustration brief-contents
  )

  @back_matter ~w(index colophon afterword bibliography glossary references back-matter backmatter)

  @guide_front ~w(cover title-page toc copyright-page dedication epigraph foreword preface acknowledgements loi lot)
  @guide_back ~w(index glossary bibliography colophon)

  defp kind(item, manifest_item, package, entry) do
    slug = slug(manifest_item.href, item.idref)
    guide_type = Map.get(package.guide, Package.resolve(package, manifest_item.href))
    guide_type = guide_type || Map.get(package.guide, manifest_item.href)

    cond do
      guide_type in @guide_front -> :front_matter
      guide_type in @guide_back -> :back_matter
      guide_type == "text" -> :body
      item.linear == "no" -> :front_matter
      slug in @front_matter -> :front_matter
      slug in @back_matter -> :back_matter
      entry && entry.class in ~w(frontmatter front-matter) -> :front_matter
      entry && entry.class in ~w(backmatter back-matter index) -> :back_matter
      true -> :body
    end
  end

  defp slug(href, idref) do
    base =
      case href do
        "" -> idref
        path -> path |> Path.basename() |> Path.rootname()
      end

    base |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  defp toc_index(files, package) do
    entries =
      cond do
        nav = read(files, package, package.nav_href) -> Toc.parse_nav(nav)
        ncx = read(files, package, package.toc_href) -> Toc.parse_ncx(ncx)
        true -> []
      end

    Toc.index(entries)
  end

  defp read(_files, _package, nil), do: nil

  defp read(files, package, href) do
    Map.get(files, Package.resolve(package, href))
  end

  # A folha é única no EPUB deste livro, mas nada impede várias; todas passam
  # pelo mesmo filtro e entram concatenadas, na ordem do manifesto.
  defp stylesheet(files, package) do
    package.manifest
    |> Map.values()
    |> Enum.filter(&(&1.media_type == "text/css"))
    |> Enum.sort_by(& &1.href)
    |> Enum.flat_map(fn item ->
      path = Package.resolve(package, item.href)

      case Map.fetch(files, path) do
        {:ok, css} -> List.wrap(Css.filter(css, files, path))
        :error -> []
      end
    end)
    |> case do
      [] -> nil
      sheets -> Enum.join(sheets, "\n\n")
    end
  end

  # Só o que os blocos de fato referenciam entra: o zip traz também a capa e os
  # ícones de aviso, e guardar imagem que ninguém aponta é peso morto no banco.
  #
  # A lista sai dos próprios blocos — do `image_path` da figura e do
  # `![alt](caminho)` das imagens no meio da frase — para não haver como o
  # leitor pedir uma imagem que a ingestão não guardou.
  @image_types %{
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".svg" => "image/svg+xml",
    ".webp" => "image/webp"
  }

  @inline_image ~r/!\[[^\]]*\]\(([^)\s]+)\)/

  @doc "Tipo de conteúdo de uma imagem pelo sufixo, ou `:error` se não for imagem."
  def image_content_type(path) do
    Map.fetch(@image_types, path |> Path.extname() |> String.downcase())
  end

  defp images(files, chapters) do
    chapters
    |> Enum.flat_map(& &1.blocks)
    |> Enum.flat_map(&referenced_paths/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn path ->
      with {:ok, content_type} <- image_content_type(path),
           {:ok, data} <- Map.fetch(files, path) do
        [{path, %{content_type: content_type, data: data, invertible: invertible?(path, data)}}]
      else
        :error -> []
      end
    end)
    |> Map.new()
  end

  # EPUB mal montado aponta para imagem que não está no pacote. O bloco não pode
  # ficar prometendo o que não existe: sem o caminho, o leitor mostra o lugar
  # reservado, e a legenda e o texto alternativo continuam contando o que havia
  # ali. Melhor que um `img` quebrado.
  defp prune_missing_images(chapters, images) do
    Enum.map(chapters, fn chapter ->
      %{chapter | blocks: Enum.map(chapter.blocks, &prune_block(&1, images))}
    end)
  end

  defp prune_block(block, images) do
    block =
      if block.image_path && not Map.has_key?(images, block.image_path),
        do: %{block | image_path: nil},
        else: block

    %{block | content: prune_inline(block.content, images)}
  end

  defp prune_inline(content, images) do
    Regex.replace(@inline_image, content, fn match, path ->
      if Map.has_key?(images, path) do
        match
      else
        Regex.run(~r/!\[([^\]]*)\]/, match) |> Enum.at(1, "")
      end
    end)
  end

  @doc """
  Indica se a imagem é traço sobre fundo transparente, e portanto pode ser
  invertida no tema escuro sem virar um negativo do que deveria mostrar.

  O canal alfa é o sinal, e ele está no cabeçalho do PNG — não precisa decodificar
  pixel. Nos dois livros medidos ele separa bem: os 191 diagramas da Manning são
  RGBA, e as 31 capturas de tela do livro do Ash são opacas. Ferramenta de
  diagrama exporta com transparência; ferramenta de captura, não.

  Uma captura salva como PNG-32 seria invertida por engano. Nenhum dos livros
  reais traz isso, e o preço do erro é uma figura estranha, não conteúdo perdido.
  """
  def invertible?(path, data) do
    case String.downcase(Path.extname(path)) do
      ".svg" -> true
      ".png" -> png_with_alpha?(data)
      _ -> false
    end
  end

  defp png_with_alpha?(
         <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", _width::32, _height::32,
           _depth::8, color_type::8, _rest::binary>> = data
       ) do
    # 4 = cinza+alfa, 6 = RGBA. A paleta (3) guarda a transparência num pedaço
    # `tRNS` à parte, então ela precisa ser procurada no corpo do arquivo.
    color_type in [4, 6] or String.contains?(data, "tRNS")
  end

  defp png_with_alpha?(_data), do: false

  defp referenced_paths(block) do
    inline = Regex.scan(@inline_image, block.content, capture: :all_but_first)

    List.wrap(block.image_path) ++ Enum.concat(inline)
  end

  defp title(%{title: title}) when is_binary(title) and title != "", do: title
  defp title(_package), do: "Livro sem título"

  # Capítulos sem bloco algum saem do livro, então a numeração absoluta precisa
  # ser refeita: `position` tem que ser contígua para o leitor paginar e para a
  # IA referenciar sem buraco.
  defp renumber(chapters) do
    {reversed, _} =
      Enum.reduce(chapters, {[], 1}, fn chapter, {acc, position} ->
        {blocks, next} =
          Enum.reduce(chapter.blocks, {[], position}, fn block, {inner, index} ->
            {[%{block | position: index} | inner], index + 1}
          end)

        {[%{chapter | blocks: Enum.reverse(blocks)} | acc], next}
      end)

    reversed
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {chapter, index} -> %{chapter | position: index} end)
  end
end
