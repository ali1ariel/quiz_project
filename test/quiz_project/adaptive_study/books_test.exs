defmodule QuizProject.AdaptiveStudy.BooksTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.Epub
  alias QuizProject.EpubFixture

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        email: "leitor#{System.unique_integer([:positive])}@teste.com",
        name: "Leitor Teste",
        password: "Password123!"
      })

    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Processando livro...",
        format: :epub,
        status: "ingesting"
      })

    %{user: user, material: material}
  end

  defp ingest(material, user, binary \\ nil) do
    {:ok, material} = Books.ingest(material, binary || EpubFixture.build(), user)
    material
  end

  describe "ingestão" do
    test "grava capítulos e blocos e conclui o material", %{material: material, user: user} do
      material = ingest(material, user)

      assert material.format == :epub
      assert material.title == "Tratado das Coisas Pequenas"
      assert material.author == "Ana Ribeiro"
      assert material.status == "draft"

      chapters = Books.list_chapters(material.id)
      assert Enum.map(chapters, & &1.position) == [1, 2, 3, 4]
      assert Enum.map(chapters, & &1.title) |> Enum.member?("1 O parafuso")
      assert Enum.map(chapters, & &1.kind) == [:front_matter, :body, :body, :back_matter]
    end

    test "block_count do capítulo bate com os blocos gravados", %{material: material, user: user} do
      material = ingest(material, user)

      for chapter <- Books.list_chapters(material.id) do
        assert chapter.block_count == length(Books.list_blocks(chapter.id))
      end
    end

    test "o livro não é guardado em texto corrido paralelo", %{material: material, user: user} do
      material = ingest(material, user)

      assert material.raw_content == ""
      assert Books.block_count(material.id) > 0
    end

    test "guarda a folha da editora já filtrada", %{material: material, user: user} do
      material = ingest(material, user)

      assert material.reader_css =~ ".qreader-book"
      refute material.reader_css =~ "@page"
    end

    test "reingerir substitui o livro em vez de duplicá-lo", %{material: material, user: user} do
      material = ingest(material, user)
      antes = Books.block_count(material.id)

      material = ingest(material, user)

      assert Books.block_count(material.id) == antes
      assert length(Books.list_chapters(material.id)) == 4
    end

    test "recusa DRM e deixa o motivo no material", %{material: material, user: user} do
      assert {:error, :drm_protected} =
               Books.ingest(material, EpubFixture.build_drm(), user)

      {:ok, material} = AdaptiveStudy.get_material(material.id, user)

      assert material.status == "failed"
      assert material.ingest_error =~ "DRM"
    end

    test "avisa por PubSub o progresso e a conclusão", %{material: material, user: user} do
      Phoenix.PubSub.subscribe(QuizProject.PubSub, Books.ingest_topic(material.id))

      ingest(material, user)

      assert_received {:ingest_progress, %{done: 1, total: 4}}
      assert_received {:ingest_progress, %{done: 4, total: 4, title: "Índice remissivo"}}
      assert_received {:ingest_finished, %{result: :ok}}
    end
  end

  describe "reconstrução" do
    test "concatenar os blocos gravados devolve o texto extraído", %{
      material: material,
      user: user
    } do
      binary = EpubFixture.build()
      {:ok, book} = Epub.parse(binary)
      material = ingest(material, user, binary)

      assert Books.material_text(material.id) == Epub.Book.to_text(book)
    end

    test "o texto de corpo exclui pré e pós-textual", %{material: material, user: user} do
      material = ingest(material, user)
      corpo = Books.material_text(material.id, body_only: true)

      assert corpo =~ "O parafuso é"
      refute corpo =~ "Todos os direitos reservados"
      refute corpo =~ "dobradiça, 2"
    end

    test "a indentação do código sobrevive à gravação", %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      code = chapter.id |> Books.list_blocks() |> Enum.find(&(&1.type == :code))

      assert code.content =~ ~r/\n {4}return/
      assert String.starts_with?(code.content, "def passo")
    end

    test "o texto do capítulo é o pedaço correspondente do livro", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      assert Books.chapter_text(chapter.id) =~ "# 1 O parafuso"
      refute Books.chapter_text(chapter.id) =~ "A dobradiça precede"
    end
  end

  describe "navegação" do
    test "abre no primeiro capítulo de conteúdo, não no copyright", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)

      assert Books.first_body_chapter(material.id).title == "1 O parafuso"
    end

    test "capítulo inexistente devolve erro em vez de estourar", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)

      assert {:error, :not_found} = Books.get_chapter(material.id, 99)
    end
  end

  describe "busca" do
    test "encontra o bloco pelo conteúdo", %{material: material, user: user} do
      material = ingest(material, user)

      assert [block | _] = Books.search(material.id, "whitworth")
      assert block.content =~ "whitworth"
      assert block.type == :list_item
    end

    test "encontra dentro do código", %{material: material, user: user} do
      material = ingest(material, user)

      assert [block] = Books.search(material.id, "comprimento")
      assert block.type == :code
    end

    test "termo curto demais não varre o livro", %{material: material, user: user} do
      material = ingest(material, user)

      assert Books.search(material.id, "a") == []
    end

    test "não vaza resultado de outro material", %{material: material, user: user} do
      ingest(material, user)

      {:ok, outro} =
        AdaptiveStudy.create_material(user, %{title: "Outro", format: :epub})

      assert Books.search(outro.id, "whitworth") == []
    end
  end

  describe "demarcação" do
    setup %{material: material, user: user} do
      %{material: ingest(material, user)}
    end

    test "liga o nó a um intervalo de blocos", %{material: material} do
      assert Books.demarcate(material.id, "no_rosca", [3, 4, 5]) == 3

      blocks = Books.blocks_for_node(material.id, "no_rosca")
      assert Enum.map(blocks, & &1.position) == [3, 4, 5]
    end

    test "o mesmo bloco pode ser coberto por mais de um nó", %{material: material} do
      Books.demarcate(material.id, "retropropagacao", [4])
      Books.demarcate(material.id, "treinamento", [4, 5])

      {:ok, chapter} = Books.get_chapter(material.id, 2)
      coverage = Books.coverage(chapter.id)

      bloco = Books.list_blocks(chapter.id) |> Enum.find(&(&1.position == 4))

      assert Enum.sort(coverage[bloco.id]) == ["retropropagacao", "treinamento"]
    end

    test "redemarcar o nó substitui a cobertura anterior", %{material: material} do
      Books.demarcate(material.id, "no_rosca", [3, 4, 5])
      Books.demarcate(material.id, "no_rosca", [6])

      assert Books.blocks_for_node(material.id, "no_rosca") |> Enum.map(& &1.position) == [6]
    end

    test "apagar o material leva a demarcação junto", %{material: material, user: user} do
      Books.demarcate(material.id, "no_rosca", [3])
      {:ok, _} = AdaptiveStudy.delete_material(material, user)

      assert Books.blocks_for_node(material.id, "no_rosca") == []
    end
  end

  describe "posição e aparência" do
    test "salva e recupera onde o usuário parou", %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 3)

      {:ok, _} =
        Books.save_position(user.id, material.id, %{
          chapter_id: chapter.id,
          block_position: 12,
          offset: 0.4
        })

      position = Books.get_position(user.id, material.id)

      assert position.chapter_id == chapter.id
      assert position.block_position == 12
      assert position.offset == 0.4
    end

    test "salvar de novo sobrescreve em vez de acumular", %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      attrs = %{chapter_id: chapter.id, block_position: 1, offset: 0.0}
      {:ok, _} = Books.save_position(user.id, material.id, attrs)
      {:ok, _} = Books.save_position(user.id, material.id, %{attrs | block_position: 9})

      assert Books.get_position(user.id, material.id).block_position == 9
    end

    test "a aparência tem padrão antes de qualquer escolha", %{user: user} do
      preference = Books.get_preferences(user.id)

      assert preference.font == :serif
      assert preference.font_size == 100
      assert preference.width == :medium
    end

    test "a aparência escolhida persiste por usuário", %{user: user} do
      {:ok, _} = Books.save_preferences(user.id, %{font: :mono, font_size: 130, width: :wide})

      preference = Books.get_preferences(user.id)

      assert preference.font == :mono
      assert preference.font_size == 130
      assert preference.width == :wide
    end
  end
end
