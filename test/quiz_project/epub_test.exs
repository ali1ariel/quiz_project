defmodule QuizProject.EpubTest do
  use ExUnit.Case, async: true

  alias QuizProject.Epub
  alias QuizProject.Epub.Block
  alias QuizProject.Epub.Book
  alias QuizProject.EpubFixture

  defp book do
    {:ok, book} = Epub.parse(EpubFixture.build())
    book
  end

  defp chapter(book, title), do: Enum.find(book.chapters, &(&1.title == title))

  defp blocks_of(book, title), do: chapter(book, title).blocks

  defp block_at(book, title, index), do: blocks_of(book, title) |> Enum.at(index)

  describe "metadados e spine" do
    test "lê título, autor, idioma e versão do OPF" do
      book = book()

      assert book.title == "Tratado das Coisas Pequenas"
      assert book.author == "Ana Ribeiro"
      assert book.language == "pt-BR"
      assert book.version == "2.0"
    end

    test "o spine dá a ordem de leitura e o NCX dá os títulos" do
      titles = Enum.map(book().chapters, & &1.title)

      assert titles == [
               "Direitos autorais",
               "1 O parafuso",
               "2 A dobradiça",
               "Índice remissivo"
             ]
    end

    test "separa pré-textual e pós-textual do corpo do livro" do
      kinds = Map.new(book().chapters, &{&1.title, &1.kind})

      assert kinds["Direitos autorais"] == :front_matter
      assert kinds["1 O parafuso"] == :body
      assert kinds["2 A dobradiça"] == :body
      assert kinds["Índice remissivo"] == :back_matter
    end

    test "lê o sumário do nav.xhtml quando o livro é EPUB 3" do
      {:ok, book} = Epub.parse(EpubFixture.build_epub3())

      assert book.version == "3.0"
      assert Enum.map(book.chapters, & &1.title) |> Enum.member?("1 O parafuso")
      assert chapter(book, "Índice remissivo").kind == :back_matter
    end
  end

  describe "numeração dos blocos" do
    test "position é absoluta e contígua no livro inteiro" do
      positions = book().chapters |> Enum.flat_map(& &1.blocks) |> Enum.map(& &1.position)

      assert positions == Enum.to_list(1..length(positions))
    end

    test "grava o id da editora, que é estável entre reingestões" do
      first = block_at(book(), "1 O parafuso", 0)

      assert first.source_id == "p1"

      # O mesmo `p1` existe em todo capítulo: a chave é (capítulo, source_id).
      assert block_at(book(), "2 A dobradiça", 0).source_id == "p1"
    end

    test "não repete source_id dentro do capítulo" do
      ids =
        book()
        |> blocks_of("1 O parafuso")
        |> Enum.map(& &1.source_id)
        |> Enum.reject(&is_nil/1)

      assert ids == Enum.uniq(ids)
    end

    test "reingerir o mesmo arquivo produz exatamente os mesmos blocos" do
      binary = EpubFixture.build()
      {:ok, primeira} = Epub.parse(binary)
      {:ok, segunda} = Epub.parse(binary)

      assert primeira.chapters == segunda.chapters
    end
  end

  describe "mapeamento de marcação para tipo de bloco" do
    test "parágrafo preserva a marcação inline em Markdown" do
      block = block_at(book(), "1 O parafuso", 1)

      assert block.type == :paragraph
      assert block.content =~ "*simples*"
      assert block.content =~ "**antigo**"
      assert block.content =~ "`screw`"
      # Referência interna do livro fica como texto: virar âncora do leitor é v2,
      # e um link para um arquivo do EPUB seria um link morto na tela.
      assert block.content =~ "Veja o capítulo seguinte e"
      refute block.content =~ "chapter-2.xhtml"
    end

    test "link para fora do livro continua sendo link" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.content =~ "manuais"))

      assert block.content =~ "[manuais de oficina](https://exemplo.org/manuais)"
    end

    test "título vira heading com o nível em Markdown" do
      block = block_at(book(), "1 O parafuso", 0)

      assert block.type == :heading
      assert block.content == "# 1 O parafuso"
      assert Block.heading_level(block) == 1
      assert Block.heading_text(block) == "1 O parafuso"
    end

    test "item de lista é bloco próprio" do
      items = book() |> blocks_of("1 O parafuso") |> Enum.filter(&(&1.type == :list_item))

      assert Enum.map(items, & &1.content) == ["Rosca métrica", "Rosca whitworth"]
    end

    test "listagem guarda título, código e anotações numeradas" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.type == :code))

      assert block.caption == "Listagem 1.1 Medindo o passo da rosca"
      assert block.annotations == ["#1 Em milímetros"]
      assert block.content =~ "def passo(voltas, comprimento):"
      assert block.content =~ "return comprimento / voltas          #1"
    end

    test "o código sobrevive com indentação e quebras de linha" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.type == :code))

      assert String.split(block.content, "\n") |> length() == 2
      assert block.content =~ ~r/\n {4}return/
    end

    test "os spans de coloração do InDesign não chegam ao bloco" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.type == :code))

      refute block.content =~ "_Code-"
      refute block.content =~ "<span"
    end

    test "callout é bloco próprio, distinto do parágrafo" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.type == :callout))

      assert block.content =~ "NOTA"
      assert block.content =~ "não é o mesmo que o avanço"
    end

    test "figura guarda legenda e texto alternativo mesmo sem a imagem" do
      block = book() |> blocks_of("1 O parafuso") |> Enum.find(&(&1.type == :figure))

      assert block.caption == "Figura 1.1 Corte longitudinal"
      assert block.annotations == ["Corte de um parafuso"]
    end

    test "barra lateral é um bloco só, com o título dentro" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :sidebar))

      assert block.content =~ "Uma digressão sobre gonzos"
      assert block.content =~ "Gonzo é o nome antigo"
    end

    test "citação vira quote" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :quote))

      assert block.content == "Toda porta gira sobre um eixo."
    end

    test "tabela é bloco único, em Markdown, com legenda" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :table))

      assert block.caption == "Tabela 2.1 Tipos de dobradiça"

      assert block.content == """
             | Tipo | Uso |
             | --- | --- |
             | Palheta | Portas internas |
             | Piano | Tampas longas |\
             """
    end

    test "listagem diagramada como tabela vira código, não tabela" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :code))

      assert block.content == """
             defmodule Dobradica do
               def girar(:esquerda), do: :abre

             end\
             """
    end

    test "a medianiz do número de linha não entra no código" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :code))

      refute block.content =~ "|"
      refute block.content =~ "codeprefix"
    end

    test "o realce da editora não deixa marcação nem espaço de largura zero" do
      block = book() |> blocks_of("2 A dobradiça") |> Enum.find(&(&1.type == :code))

      refute block.content =~ "**"
      refute block.content =~ "\u{200B}"
    end

    test "tabela de dados com cabeçalho continua sendo tabela" do
      blocks = book() |> blocks_of("2 A dobradiça")

      assert Enum.count(blocks, &(&1.type == :table)) == 1
      assert Enum.count(blocks, &(&1.type == :code)) == 1
    end

    test "célula de tabela não vira parágrafo solto" do
      paragraphs = book() |> blocks_of("2 A dobradiça") |> Enum.filter(&(&1.type == :paragraph))

      refute Enum.any?(paragraphs, &(&1.content == "Palheta"))
    end
  end

  describe "reconstrução" do
    test "concatenar os blocos na ordem devolve o texto do livro" do
      book = book()

      esperado =
        book.chapters
        |> Enum.flat_map(& &1.blocks)
        |> Enum.sort_by(& &1.position)
        |> Enum.map_join("\n\n", & &1.content)

      assert Book.to_text(book) == esperado
    end

    test "o texto de corpo exclui pré e pós-textual" do
      book = book()

      refute Book.body_text(book) =~ "Todos os direitos reservados"
      refute Book.body_text(book) =~ "dobradiça, 2"
      assert Book.body_text(book) =~ "O parafuso é"
    end
  end

  describe "folha de estilo da editora" do
    test "descarta a herança de página impressa" do
      css = book().css

      refute css =~ "@page"
      refute css =~ "font-family: Verdana"
      refute css =~ "page-break-inside"
      refute css =~ "position: absolute"
    end

    test "não deixa nenhuma regra escapar do contêiner de leitura" do
      selectors =
        book().css
        |> String.split("\n")
        |> Enum.filter(&String.ends_with?(&1, "{"))
        |> Enum.reject(&String.starts_with?(&1, "@"))

      assert selectors != []
      assert Enum.all?(selectors, &String.starts_with?(&1, ".qreader-book"))
    end

    test "traduz cor chapada em token do tema" do
      css = book().css

      refute css =~ "#020056"
      refute css =~ "color: black"
      assert css =~ ".qreader-book .listing-container-h5"
      assert css =~ "color: var(--color-primary-content)"
      assert css =~ "background: var(--color-primary)"
    end

    test "mantém a semântica que o tema não sabe reconstruir" do
      css = book().css

      assert css =~ "font-weight: bold"
      assert css =~ "text-transform: uppercase"
      assert css =~ "border-collapse: collapse"
      assert css =~ "font-variant-ligatures: none"
    end

    test "descarta @media print e mantém a fonte monoespaçada do livro" do
      css = book().css

      refute css =~ "@media print"
      assert css =~ "font-family: 'Mono do Livro', monospace"
    end

    test "embute a fonte declarada em @font-face como data: URI" do
      css = book().css

      assert css =~ "@font-face"
      assert css =~ "font-family: 'Mono do Livro'"
      assert css =~ "src: url(data:font/woff2;base64,"
      assert css =~ Base.encode64("wOF2-conteudo-falso-de-fonte")
    end
  end

  describe "o que se recusa a abrir" do
    test "recusa DRM quando o conteúdo do spine está cifrado" do
      assert {:error, :drm_protected} = Epub.parse(EpubFixture.build_drm())
      assert Epub.error_message(:drm_protected) =~ "DRM"
    end

    test "abre o livro cuja cifra atinge só a fonte" do
      assert {:ok, book} = Epub.parse(EpubFixture.build_obfuscated_font())
      assert length(book.chapters) == 4
    end

    test "recusa layout fixo" do
      assert {:error, :fixed_layout} = Epub.parse(EpubFixture.build_fixed_layout())
      assert Epub.error_message(:fixed_layout) =~ "layout fixo"
    end

    test "recusa arquivo que não é EPUB" do
      {:ok, {_name, zip}} = :zip.create(~c"x.zip", [{~c"leia.txt", "oi"}], [:memory])

      assert {:error, :not_an_epub} = Epub.parse(zip)
    end

    test "recusa binário que não é sequer um zip" do
      assert {:error, :corrupt_archive} = Epub.parse("isto não é um zip")
    end

    test "a verificação do upload recusa sem extrair o livro inteiro" do
      assert {:error, :drm_protected} = Epub.inspect_package(EpubFixture.build_drm())

      assert {:ok, %{title: "Tratado das Coisas Pequenas", chapter_count: 4}} =
               Epub.inspect_package(EpubFixture.build())
    end
  end

  describe "progresso" do
    test "avisa a cada capítulo processado" do
      pai = self()

      {:ok, _book} =
        Epub.parse(EpubFixture.build(), on_chapter: &send(pai, {:progresso, &1}))

      assert_received {:progresso, {1, 4, "Direitos autorais"}}
      assert_received {:progresso, {4, 4, "Índice remissivo"}}
    end
  end

  # O livro real fica fora do repositório: 23MB e obra comercial. O teste passa
  # sozinho quando o arquivo não está na máquina.
  describe "livro real" do
    @describetag :epub_real

    setup do
      path = Path.expand("~/Downloads/Deep_Learning_with_Python_Third_Edition.epub")

      if File.exists?(path) do
        {:ok, binary: File.read!(path)}
      else
        {:ok, skip: true}
      end
    end

    test "segmenta o livro inteiro sem IA", context do
      if context[:skip] do
        :ok
      else
        {:ok, book} = Epub.parse(context.binary)

        assert book.title == "Deep Learning with Python, Third Edition"
        assert book.version == "2.0"

        corpo = Enum.filter(book.chapters, &(&1.kind == :body))
        assert length(corpo) == 20

        assert Enum.count(book.chapters, &(&1.kind == :front_matter)) >= 8
        assert Enum.any?(book.chapters, &(&1.kind == :back_matter))

        assert Book.block_count(book) > 6_000
        assert String.length(Book.body_text(book)) > 1_000_000
      end
    end
  end
end
