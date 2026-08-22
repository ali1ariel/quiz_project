defmodule QuizProject.AdaptiveStudy.BooksTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.AdaptiveStudy.ImageStore
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

  describe "imagens" do
    test "grava em disco, com o tipo vindo do sufixo", %{material: material, user: user} do
      material = ingest(material, user)

      assert {:ok, file, "image/png"} =
               ImageStore.fetch(material.id, "OEBPS/Images/parafuso.png")

      assert File.read!(file) == EpubFixture.png()
    end

    test "mantém a estrutura de pastas do livro", %{material: material, user: user} do
      material = ingest(material, user)

      assert File.regular?(
               Path.join(ImageStore.material_dir(material.id), "OEBPS/Images/parafuso.png")
             )
    end

    test "o bloco de figura aponta para a imagem gravada", %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      figura = chapter.id |> Books.list_blocks() |> Enum.find(&(&1.type == :figure))

      assert figura.image_path == "OEBPS/Images/parafuso.png"
      assert {:ok, _file, _type} = ImageStore.fetch(material.id, figura.image_path)
    end

    test "imagem não referenciada não vai para o disco", %{material: material, user: user} do
      material = ingest(material, user)

      assert ImageStore.fetch(material.id, "OEBPS/Images/nao-referenciada.png") == :error
    end

    test "reingerir substitui as imagens sem deixar órfã", %{material: material, user: user} do
      material = ingest(material, user)

      orfa = Path.join(ImageStore.material_dir(material.id), "OEBPS/Images/edicao-antiga.png")
      File.write!(orfa, "sobra")

      material = ingest(material, user)

      assert {:ok, _file, _type} = ImageStore.fetch(material.id, "OEBPS/Images/parafuso.png")
      refute File.exists?(orfa)
    end

    test "apagar o livro leva as imagens junto", %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, _} = AdaptiveStudy.delete_material(material, user)

      assert ImageStore.fetch(material.id, "OEBPS/Images/parafuso.png") == :error
      refute File.exists?(ImageStore.material_dir(material.id))
    end

    test "não devolve imagem de outro livro", %{material: material, user: user} do
      ingest(material, user)

      {:ok, outro} = AdaptiveStudy.create_material(user, %{title: "Outro", format: :epub})

      assert ImageStore.fetch(outro.id, "OEBPS/Images/parafuso.png") == :error
    end

    test "guarda quais imagens podem ser invertidas no tema escuro", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)

      assert material.image_flags == %{
               "OEBPS/Images/parafuso.png" => true,
               "OEBPS/Images/equacao.png" => true
             }

      refute Map.has_key?(material.image_flags, "OEBPS/Images/captura.png")
    end

    test "caminho que tenta sair da pasta do material é recusado", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)

      for tentativa <- [
            "../#{material.id}/OEBPS/Images/parafuso.png",
            "../../../etc/passwd",
            "/etc/passwd",
            "OEBPS/../../escapou.png"
          ] do
        assert ImageStore.fetch(material.id, tentativa) == :error
      end
    end
  end

  describe "estimativa de tokens" do
    test "pondera código mais pesado que prosa", %{material: _m} do
      prosa = [%{type: :paragraph, content: String.duplicate("a", 400)}]
      codigo = [%{type: :code, content: String.duplicate("a", 400)}]

      assert Books.estimate_tokens(prosa) == 100
      assert Books.estimate_tokens(codigo) == 143
      assert Books.estimate_tokens(codigo) > Books.estimate_tokens(prosa)
    end

    test "soma os blocos e ignora tipo desconhecido usando o padrão" do
      blocos = [
        %{type: :paragraph, content: String.duplicate("a", 400)},
        %{type: :table, content: String.duplicate("a", 300)}
      ]

      assert Books.estimate_tokens(blocos) == 200
    end

    test "capítulo vazio estima zero" do
      assert Books.estimate_tokens([]) == 0
    end

    test "é gravado na ingestão, sem precisar dos blocos depois", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)

      for chapter <- Books.list_chapters(material.id) do
        blocos = Books.list_blocks(chapter.id)
        assert chapter.estimated_tokens == Books.estimate_tokens(blocos)
      end
    end

    test "sinaliza risco só acima do limiar" do
      refute Books.curation_risky?(Books.safe_curation_tokens())
      assert Books.curation_risky?(Books.safe_curation_tokens() + 1)
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

  describe "texto do capítulo preparado para IA" do
    test "cerca o bloco de código com legenda e anotações, sem mudar o resto", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      texto = Books.chapter_text_for_curation(chapter.id)

      assert texto =~ "Listagem 1.1 Medindo o passo da rosca"
      assert texto =~ "```\ndef passo(voltas, comprimento):"
      assert texto =~ "- #1 Em milímetros"

      # o resto do capítulo continua igual à reconstrução verbatim
      assert texto =~ "O parafuso é *simples* e **antigo**"
    end

    test "cada bloco sai marcado com a própria posição absoluta", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      posicoes = chapter.id |> Books.list_blocks() |> Enum.map(& &1.position)
      texto = Books.chapter_text_for_curation(chapter.id)

      for posicao <- posicoes, do: assert(texto =~ "[##{posicao}]")
    end

    test "sem os marcadores de posição, o texto é igual à reconstrução verbatim", %{
      material: material,
      user: user
    } do
      material = ingest(material, user)
      {:ok, indice} = Books.get_chapter(material.id, 4)

      sem_marcadores =
        Books.chapter_text_for_curation(indice.id)
        |> String.replace(~r/\[#\d+\]\n/, "")

      assert sem_marcadores == Books.chapter_text(indice.id)
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
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)
      %{material: material, chapter: chapter}
    end

    test "liga o nó a um intervalo de blocos", %{chapter: chapter} do
      assert Books.demarcate(chapter, "no_rosca", [3, 4, 5]) == 3

      blocks = Books.blocks_for_node(chapter.id, "no_rosca")
      assert Enum.map(blocks, & &1.position) == [3, 4, 5]
    end

    test "o mesmo bloco pode ser coberto por mais de um nó", %{chapter: chapter} do
      Books.demarcate(chapter, "retropropagacao", [4])
      Books.demarcate(chapter, "treinamento", [4, 5])

      coverage = Books.coverage(chapter.id)

      bloco = Books.list_blocks(chapter.id) |> Enum.find(&(&1.position == 4))

      assert Enum.sort(coverage[bloco.id]) == ["retropropagacao", "treinamento"]
    end

    test "redemarcar o nó substitui a cobertura anterior", %{chapter: chapter} do
      Books.demarcate(chapter, "no_rosca", [3, 4, 5])
      Books.demarcate(chapter, "no_rosca", [6])

      assert Books.blocks_for_node(chapter.id, "no_rosca") |> Enum.map(& &1.position) == [6]
    end

    test "apagar o material leva a demarcação junto", %{material: material, chapter: chapter, user: user} do
      Books.demarcate(chapter, "no_rosca", [3])
      {:ok, _} = AdaptiveStudy.delete_material(material, user)

      assert Books.blocks_for_node(chapter.id, "no_rosca") == []
    end

    test "dois capítulos do mesmo livro podem reusar o mesmo node_id sem colidir",
         %{material: material} do
      {:ok, chapter1} = Books.get_chapter(material.id, 1)
      {:ok, chapter2} = Books.get_chapter(material.id, 2)

      posicoes_1 = chapter1.id |> Books.list_blocks() |> Enum.map(& &1.position) |> Enum.take(1)
      posicoes_2 = chapter2.id |> Books.list_blocks() |> Enum.map(& &1.position) |> Enum.take(2)

      Books.demarcate(chapter1, "no_1", posicoes_1)
      Books.demarcate(chapter2, "no_1", posicoes_2)

      blocos_1 = Books.blocks_for_node(chapter1.id, "no_1")
      blocos_2 = Books.blocks_for_node(chapter2.id, "no_1")

      assert Enum.map(blocos_1, & &1.position) == posicoes_1
      assert Enum.map(blocos_2, & &1.position) == posicoes_2
      assert posicoes_1 != posicoes_2
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

  describe "marcação e notas" do
    setup %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)
      block = chapter.id |> Books.list_blocks() |> List.first()

      %{material: material, chapter: chapter, block: block}
    end

    test "marca um trecho do bloco e aparece agrupada por bloco", %{
      user: user,
      chapter: chapter,
      block: block
    } do
      {:ok, highlight} =
        Books.create_highlight(user, chapter, block.position, %{
          start_offset: 0,
          end_offset: 5,
          quote: "trecho",
          color: :green
        })

      assert highlight.block_id == block.id
      assert highlight.note == nil

      grouped = Books.list_highlights(chapter.id, user.id)
      assert Map.keys(grouped) == [block.id]
      assert [%{id: id}] = Map.fetch!(grouped, block.id)
      assert id == highlight.id
    end

    test "posição de bloco inexistente não marca nada", %{user: user, chapter: chapter} do
      assert {:error, :block_not_found} =
               Books.create_highlight(user, chapter, 999_999, %{
                 start_offset: 0,
                 end_offset: 3,
                 quote: "abc",
                 color: :yellow
               })
    end

    # A seleção num bloco de código serve para copiar o trecho, não para
    # marcar — o cliente já nem mostra a barra ali; isto cobre quem manda o
    # evento direto pelo socket, sem passar pela interface.
    test "bloco de código não marca", %{user: user, chapter: chapter} do
      codigo = Enum.find(Books.list_blocks(chapter.id), &(&1.type == :code))
      assert codigo

      assert {:error, :unsupported_block_type} =
               Books.create_highlight(user, chapter, codigo.position, %{
                 start_offset: 0,
                 end_offset: 3,
                 quote: "def",
                 color: :yellow
               })
    end

    test "só o dono lê a própria marcação", %{user: user, chapter: chapter, block: block} do
      {:ok, highlight} =
        Books.create_highlight(user, chapter, block.position, %{
          start_offset: 0,
          end_offset: 3,
          quote: "abc",
          color: :yellow
        })

      {:ok, outro} =
        Accounts.register_user(%{
          email: "outro#{System.unique_integer([:positive])}@teste.com",
          name: "Outro leitor",
          password: "Password123!"
        })

      assert {:ok, %{id: id}} = Books.get_own_highlight(highlight.id, user.id)
      assert id == highlight.id
      assert {:error, :unauthorized} = Books.get_own_highlight(highlight.id, outro.id)
    end

    test "atualizar grava nota e cor", %{user: user, chapter: chapter, block: block} do
      {:ok, highlight} =
        Books.create_highlight(user, chapter, block.position, %{
          start_offset: 0,
          end_offset: 3,
          quote: "abc",
          color: :yellow
        })

      {:ok, updated} = Books.update_highlight(highlight, %{note: "Lembrar disso", color: :pink})

      assert updated.note == "Lembrar disso"
      assert updated.color == :pink
    end

    test "apagar remove a marcação", %{user: user, chapter: chapter, block: block} do
      {:ok, highlight} =
        Books.create_highlight(user, chapter, block.position, %{
          start_offset: 0,
          end_offset: 3,
          quote: "abc",
          color: :yellow
        })

      assert :ok = Books.delete_highlight(highlight)
      assert Books.list_highlights(chapter.id, user.id) == %{}
    end

    test "a lista do livro traz capítulo e posição do bloco junto", %{
      material: material,
      user: user,
      chapter: chapter,
      block: block
    } do
      {:ok, _highlight} =
        Books.create_highlight(user, chapter, block.position, %{
          start_offset: 0,
          end_offset: 3,
          quote: "abc",
          color: :yellow
        })

      assert [entry] = Books.list_highlights_for_material(user.id, material.id)
      assert entry.chapter.id == chapter.id
      assert entry.block_position == block.position
    end
  end

  describe "curadoria de capítulo por IA" do
    setup %{material: material, user: user} do
      material = ingest(material, user)
      {:ok, chapter} = Books.get_chapter(material.id, 2)
      %{chapter: chapter}
    end

    test "capítulo novo começa sem curadoria", %{chapter: chapter} do
      assert Books.chapter_ai_state(chapter) == :none
      assert chapter.curated_material_id == nil
    end

    test "cria um Material de Estudo em texto a partir do capítulo e conclui a curadoria", %{
      chapter: chapter,
      user: user
    } do
      {:ok, processing} = Books.curate_chapter_async(chapter, user)
      assert processing.curation_status == :processing
      assert Books.chapter_ai_state(processing) == :processing

      finished = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))
      assert finished.curation_status == :done
      assert Books.chapter_ai_state(finished) == :done

      {:ok, gerado} = AdaptiveStudy.get_material(finished.curated_material_id, user)
      assert gerado.format == :text
      assert gerado.title =~ chapter.title
      assert gerado.raw_content == Books.chapter_text_for_curation(chapter.id)
      assert gerado.mindmap_tree != %{}
    end

    test "clicar de novo enquanto processa não reprocessa (guard atômico no banco)", %{
      chapter: chapter,
      user: user
    } do
      {:ok, _} = Books.curate_chapter_async(chapter, user)

      finished = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert {:error, :already_processing} = Books.curate_chapter_async(finished, user)

      materiais_gerados =
        AdaptiveStudy.list_materials(user) |> Enum.count(&(&1.format == :text))

      assert materiais_gerados == 1
    end

    test "capítulo já curado não é reprocessado", %{chapter: chapter, user: user} do
      {:ok, _} = Books.curate_chapter_async(chapter, user)
      done = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert {:error, :already_processing} = Books.curate_chapter_async(done, user)
    end

    test "material gerado apagado libera o capítulo para reprocessar", %{
      chapter: chapter,
      user: user
    } do
      {:ok, _} = Books.curate_chapter_async(chapter, user)
      done = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      {:ok, gerado} = AdaptiveStudy.get_material(done.curated_material_id, user)
      {:ok, _} = AdaptiveStudy.delete_material(gerado, user)

      orfao = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))
      assert orfao.curated_material_id == nil
      assert Books.chapter_ai_state(orfao) == :none

      assert {:ok, reprocessando} = Books.curate_chapter_async(orfao, user)
      assert reprocessando.curation_status == :processing
    end

    test "todo bloco de corpo do capítulo fica coberto por ao menos um nó folha", %{
      chapter: chapter,
      user: user
    } do
      {:ok, _} = Books.curate_chapter_async(chapter, user)

      coverage = Books.coverage(chapter.id)
      blocos = Books.list_blocks(chapter.id)

      for bloco <- blocos do
        assert Map.get(coverage, bloco.id, []) != [],
               "bloco na posição #{bloco.position} não foi coberto por nenhum nó"
      end
    end

    test "posição inválida devolvida pela IA não grava nada e não estoura", %{
      chapter: chapter,
      user: user
    } do
      {:ok, _} = Books.curate_chapter_async(chapter, user)

      finished = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))
      {:ok, gerado} = AdaptiveStudy.get_material(finished.curated_material_id, user)

      # Redemarca um nó que já existe com uma posição de outro capítulo, como se
      # a IA tivesse errado — não deve estourar, e a posição inválida não entra.
      node_id =
        gerado.mindmap_tree["nodes"]
        |> AdaptiveStudy.flatten_nodes()
        |> Enum.find(&(&1["children"] in [[], nil]))
        |> Map.fetch!("id")

      assert Books.demarcate(chapter, node_id, [999_999]) == 0
      assert Books.blocks_for_node(chapter.id, node_id) == []
    end
  end

  describe "previsão de custo da curadoria" do
    # A razão da saída saiu de comparação com fatura real, não de intuição: a
    # versão anterior assumia saída = entrada e errava por 2,3x, porque ignorava
    # a estrutura JSON e os tokens de raciocínio, cobrados como saída.
    test "a saída prevista é maior que a entrada" do
      previsao = Books.curation_forecast(21_709)

      assert previsao.input == 21_709
      assert previsao.output > previsao.input

      # Confere com a medição: US$ 1,47 em claude-opus-5 implica ~54.500 de saída.
      assert_in_delta previsao.output, 54_500, 1_000
    end

    test "capítulo sem conteúdo não prevê nada" do
      assert %{input: 0, output: 0} = Books.curation_forecast(0)
    end

    # Sem curadoria feita a previsão é suposição, e a tela precisa poder dizer
    # isso — número sem procedência parece tão confiável quanto medição.
    test "sem medição nenhuma a previsão se declara estimativa" do
      assert Books.measured_output_ratio() == nil
      assert %{basis: :assumed} = Books.curation_forecast(1_000)
    end

    # O limiar existe porque saída e raciocínio dividem um teto de 64k tokens no
    # Claude: acima de ~25.600 de entrada a resposta não cabe.
    test "o limiar de risco fica abaixo do ponto de estouro" do
      limiar = Books.safe_curation_tokens()

      assert Books.curation_risky?(limiar + 1)
      refute Books.curation_risky?(limiar)
      assert Books.curation_forecast(limiar).output < 64_000
    end
  end
end
