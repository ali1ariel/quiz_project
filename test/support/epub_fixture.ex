defmodule QuizProject.EpubFixture do
  @moduledoc """
  EPUB sintético de poucos KB, montado em memória.

  O livro real (23MB, obra comercial) não vai para o repositório, mas a suíte
  precisa de um EPUB que exercite cada linha da tabela de mapeamento de blocos.
  Este aqui é escrito em heredoc justamente para o diff mostrar o que mudou —
  um `.zip` versionado seria opaco na revisão.
  """

  @doc """
  Binário `.epub`. `overrides` substitui ou adiciona arquivos do pacote, que é
  como os casos de recusa (DRM, layout fixo) são montados a partir do mesmo
  livro.
  """
  def build(overrides \\ %{}) do
    entries =
      base_files()
      |> Map.merge(overrides)
      # `nil` remove o arquivo do pacote — é assim que a variante EPUB 3 tira o
      # `toc.ncx` de cena.
      |> Enum.reject(fn {_path, content} -> is_nil(content) end)
      |> Enum.map(fn {path, content} -> {String.to_charlist(path), content} end)

    {:ok, {_name, binary}} = :zip.create(~c"fixture.epub", entries, [:memory])
    binary
  end

  @doc "Pacote EPUB 3: `nav.xhtml` no lugar do `toc.ncx`."
  def build_epub3 do
    build(%{
      "OEBPS/content.opf" => opf_epub3(),
      "OEBPS/Text/nav.xhtml" => nav(),
      "OEBPS/toc.ncx" => nil
    })
  end

  @doc "Pacote com DRM: o capítulo do spine aparece cifrado no `encryption.xml`."
  def build_drm do
    build(%{"META-INF/encryption.xml" => encryption("OEBPS/Text/chapter-1.xhtml")})
  end

  @doc "Pacote com fonte ofuscada — cifra fonte, não conteúdo, e por isso abre."
  def build_obfuscated_font do
    build(%{"META-INF/encryption.xml" => encryption("OEBPS/Fonts/mono.woff2")})
  end

  @doc "Pacote de layout fixo (quadrinho, livro ilustrado)."
  def build_fixed_layout do
    fixed =
      String.replace(
        opf(),
        "</metadata>",
        ~s(  <meta property="rendition:layout">pre-paginated</meta>\n  </metadata>)
      )

    build(%{"OEBPS/content.opf" => fixed})
  end

  # PNG de 1x1 transparente: o menor arquivo que ainda é uma imagem de verdade,
  # com cabeçalho válido, para o teste exercitar o caminho inteiro.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
       )

  # PNG de 1x1 opaco, em RGB e sem canal alfa: é a forma que ferramenta de
  # captura de tela exporta, e o contraponto do diagrama transparente.
  @png_opaco Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
             )

  @doc "Bytes do PNG transparente que a fixture embute."
  def png, do: @png

  @doc "Bytes do PNG opaco que a fixture embute."
  def png_opaco, do: @png_opaco

  defp base_files do
    %{
      "mimetype" => "application/epub+zip",
      "META-INF/container.xml" => container(),
      "OEBPS/content.opf" => opf(),
      "OEBPS/toc.ncx" => ncx(),
      "OEBPS/Styles/style.css" => css(),
      "OEBPS/Fonts/mono.woff2" => "wOF2-conteudo-falso-de-fonte",
      "OEBPS/Images/parafuso.png" => @png,
      "OEBPS/Images/equacao.png" => @png,
      "OEBPS/Images/captura.png" => @png_opaco,
      "OEBPS/Images/nao-referenciada.png" => @png,
      "OEBPS/Text/copyright.xhtml" => copyright(),
      "OEBPS/Text/chapter-1.xhtml" => chapter_one(),
      "OEBPS/Text/chapter-2.xhtml" => chapter_two(),
      "OEBPS/Text/index.xhtml" => index_page()
    }
  end

  defp container do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """
  end

  defp opf do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="pub-id" version="2.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
        <dc:title>Tratado das Coisas Pequenas</dc:title>
        <dc:creator>Ana Ribeiro</dc:creator>
        <dc:language>pt-BR</dc:language>
        <dc:identifier id="pub-id">urn:isbn:9780000000001</dc:identifier>
      </metadata>
      <manifest>
        <item href="Text/copyright.xhtml" id="copyright" media-type="application/xhtml+xml"/>
        <item href="Text/chapter-1.xhtml" id="chapter-1" media-type="application/xhtml+xml"/>
        <item href="Text/chapter-2.xhtml" id="chapter-2" media-type="application/xhtml+xml"/>
        <item href="Text/index.xhtml" id="index" media-type="application/xhtml+xml"/>
        <item href="Styles/style.css" id="css" media-type="text/css"/>
        <item href="Fonts/mono.woff2" id="mono" media-type="font/woff2"/>
        <item href="Images/parafuso.png" id="img-parafuso" media-type="image/png"/>
        <item href="Images/equacao.png" id="img-equacao" media-type="image/png"/>
        <item href="Images/captura.png" id="img-captura" media-type="image/png"/>
        <item href="Images/nao-referenciada.png" id="img-sobra" media-type="image/png"/>
        <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
      </manifest>
      <spine toc="ncx">
        <itemref idref="copyright"/>
        <itemref idref="chapter-1"/>
        <itemref idref="chapter-2"/>
        <itemref idref="index"/>
      </spine>
      <guide>
        <reference href="Text/copyright.xhtml" title="Copyright" type="copyright-page"/>
      </guide>
    </package>
    """
  end

  defp opf_epub3 do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="pub-id" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Tratado das Coisas Pequenas</dc:title>
        <dc:creator>Ana Ribeiro</dc:creator>
        <dc:language>pt-BR</dc:language>
        <dc:identifier id="pub-id">urn:isbn:9780000000001</dc:identifier>
      </metadata>
      <manifest>
        <item href="Text/nav.xhtml" id="nav" media-type="application/xhtml+xml" properties="nav"/>
        <item href="Text/copyright.xhtml" id="copyright" media-type="application/xhtml+xml"/>
        <item href="Text/chapter-1.xhtml" id="chapter-1" media-type="application/xhtml+xml"/>
        <item href="Text/chapter-2.xhtml" id="chapter-2" media-type="application/xhtml+xml"/>
        <item href="Text/index.xhtml" id="index" media-type="application/xhtml+xml"/>
        <item href="Styles/style.css" id="css" media-type="text/css"/>
        <item href="Fonts/mono.woff2" id="mono" media-type="font/woff2"/>
      </manifest>
      <spine>
        <itemref idref="copyright"/>
        <itemref idref="chapter-1"/>
        <itemref idref="chapter-2"/>
        <itemref idref="index"/>
      </spine>
    </package>
    """
  end

  defp ncx do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
      <navMap>
        <navPoint class="frontmatter" id="n1" playOrder="1">
          <navLabel><text>Direitos autorais</text></navLabel>
          <content src="Text/copyright.xhtml"/>
        </navPoint>
        <navPoint class="chapter" id="n2" playOrder="2">
          <navLabel><text>1 O parafuso</text></navLabel>
          <content src="Text/chapter-1.xhtml"/>
          <navPoint class="section" id="n2a" playOrder="3">
            <navLabel><text>1.1 A rosca</text></navLabel>
            <content src="Text/chapter-1.xhtml#p4"/>
          </navPoint>
        </navPoint>
        <navPoint class="chapter" id="n3" playOrder="4">
          <navLabel><text>2 A dobradiça</text></navLabel>
          <content src="Text/chapter-2.xhtml"/>
        </navPoint>
        <navPoint class="index" id="n4" playOrder="5">
          <navLabel><text>Índice remissivo</text></navLabel>
          <content src="Text/index.xhtml"/>
        </navPoint>
      </navMap>
    </ncx>
    """
  end

  defp nav do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <body>
        <nav epub:type="toc">
          <ol>
            <li><a href="copyright.xhtml">Direitos autorais</a></li>
            <li>
              <a href="chapter-1.xhtml">1 O parafuso</a>
              <ol><li><a href="chapter-1.xhtml#p4">1.1 A rosca</a></li></ol>
            </li>
            <li><a href="chapter-2.xhtml">2 A dobradiça</a></li>
            <li><a href="index.xhtml">Índice remissivo</a></li>
          </ol>
        </nav>
      </body>
    </html>
    """
  end

  defp css do
    """
    @page { margin-bottom: 5pt; }

    body {
      margin: 0 5pt;
      font-family: Verdana;
      color: black;
    }

    .readable-text p { color: black; }

    .callout-container { background: #E6E6E6; padding: 0.5rem; }

    .listing-container-h5 { color: white !important; background: #020056; }

    .code-area { background: #f2f2f2; page-break-inside: avoid; }

    .faux-counter { position: absolute; left: -1.5em; }

    table, td { border: 1px solid #cccccc; border-collapse: collapse; }

    .destaque { font-weight: bold; text-transform: uppercase; }

    @media print { .readable-text { font-size: 9pt; } }

    @font-face {
      font-family: 'Mono do Livro';
      font-style: normal;
      font-weight: 400;
      src: url('../Fonts/mono.woff2') format('woff2');
    }

    pre.code-area { font-family: 'Mono do Livro', monospace; font-variant-ligatures: none; }
    """
  end

  defp copyright do
    page("""
    <div class="readable-text" id="p1"><p>Todos os direitos reservados.</p></div>
    """)
  end

  defp chapter_one do
    page("""
    <div class="readable-text" id="p1">
      <h1>1 O parafuso</h1>
    </div>
    <div class="readable-text" id="p2">
      <p>O parafuso é <em>simples</em> e <strong>antigo</strong>, e chama-se
         <code>screw</code> em inglês. Veja
         <a href="chapter-2.xhtml">o capítulo seguinte</a> e os
         <a href="https://exemplo.org/manuais">manuais de oficina</a>.</p>
    </div>
    <ul>
      <li class="readable-text" id="p3">Rosca métrica</li>
      <li class="readable-text" id="p4">Rosca whitworth</li>
    </ul>
    <div class="listing-container" id="p5">
      <h5 class="listing-container-h5">Listagem 1.1 Medindo o passo da rosca</h5>
      <div class="code-area-container">
        <pre class="code-area"><span class="_Code-Gray">def</span> passo<span class="_Code-Gray">(</span>voltas<span class="_Code-Gray">,</span> comprimento<span class="_Code-Gray">)</span>:
        <span class="_Code-Blue">return</span> comprimento / voltas          #1</pre>
        <div class="code-annotations-overlay-container"> #1 Em milímetros
          <br/>
        </div>
      </div>
    </div>
    <div class="readable-text print-book-callout" id="p6">
      <p><span class="print-book-callout-head">NOTA</span> O passo não é o mesmo que o avanço.</p>
    </div>
    <div class="figure-container" id="p7">
      <img alt="Corte de um parafuso" src="../Images/parafuso.png"/>
      <h5 class="figure-container-h5">Figura 1.1 Corte longitudinal</h5>
    </div>
    <div class="figure-container" id="p8">
      <img alt="Tela da bancada" src="../Images/captura.png"/>
      <h5 class="figure-container-h5">Figura 1.2 A bancada montada</h5>
    </div>
    """)
  end

  defp chapter_two do
    page("""
    <div class="readable-text" id="p1"><h1>2 A dobradiça</h1></div>
    <div class="readable-text" id="p2">
      <p>A dobradiça precede o parafuso, girando sobre o eixo
         <img alt="eixo" src="../Images/equacao.png"/> descrito acima.</p>
    </div>
    <div class="callout-container sidebar-container">
      <div class="readable-text" id="p3"><h5 class="callout-container-h5">Uma digressão sobre gonzos</h5></div>
      <div class="readable-text" id="p4"><p>Gonzo é o nome antigo da dobradiça.</p></div>
    </div>
    <blockquote id="p5"><p>Toda porta gira sobre um eixo.</p></blockquote>
    <div class="browsable-table-container" id="p6">
      <h5>Tabela 2.1 Tipos de dobradiça</h5>
      <table>
        <thead><tr><th><p>Tipo</p></th><th><p>Uso</p></th></tr></thead>
        <tbody>
          <tr><td><p>Palheta</p></td><td><p>Portas internas</p></td></tr>
          <tr><td><p>Piano</p></td><td><p>Tampas longas</p></td></tr>
        </tbody>
      </table>
    </div>
    <div class="livecodelozenge"><a href="http://exemplo.org/codigo">02/lib/dobradica.ex</a></div>
    <table class="processedcode" id="p7">
      <tr><td class="codeinfo"><span class="codeprefix"> </span></td><td class="codeline">defmodule <strong class="kw">Dobradica</strong> <strong class="kw">do</strong></td></tr>
      <tr><td class="codeinfo"><span class="codeprefix"> </span></td><td class="codeline">  def girar(<em class="string">:esquerda</em>), <strong class="kw">do</strong>: <em class="string">:abre</em></td></tr>
      <tr><td class="codeinfo"><span class="codeprefix"> </span></td><td class="codeline"></td></tr>
      <tr><td class="codeinfo"><span class="codeprefix"> </span></td><td class="codeline"><strong class="kw">end</strong></td></tr>
    </table>
    """)
  end

  defp index_page do
    page("""
    <div class="readable-text" id="p1"><h1>Índice remissivo</h1></div>
    <div class="readable-text" id="p2"><p>dobradiça, 2</p></div>
    """)
  end

  defp page(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><link href="../Styles/style.css" rel="stylesheet" type="text/css"/></head>
      <body>
    #{body}
      </body>
    </html>
    """
  end

  defp encryption(uri) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
        <EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
        <CipherData><CipherReference URI="#{uri}"/></CipherData>
      </EncryptedData>
    </encryption>
    """
  end
end
