defmodule QuizProjectWeb.ContentsReadLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.EpubFixture

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Processando livro...",
        format: :epub,
        status: "ingesting"
      })

    {:ok, material} = Books.ingest(material, EpubFixture.build(), user)

    %{material: material}
  end

  describe "abertura" do
    test "sem capítulo na URL, abre no primeiro capítulo de conteúdo", %{
      conn: conn,
      material: material
    } do
      assert {:error, {:live_redirect, %{to: destino}}} =
               live(conn, ~p"/contents/#{material.id}")

      assert destino == ~p"/contents/#{material.id}/2"

      {:ok, _view, html} = live(conn, destino)
      assert html =~ "1 O parafuso"
      refute html =~ "Todos os direitos reservados"
    end

    test "continua de onde parou quando já há posição salva", %{
      conn: conn,
      material: material,
      user: user
    } do
      {:ok, chapter} = Books.get_chapter(material.id, 3)

      {:ok, _} =
        Books.save_position(user.id, material.id, %{
          chapter_id: chapter.id,
          block_position: 12,
          offset: 0.3
        })

      assert {:error, {:live_redirect, %{to: destino}}} =
               live(conn, ~p"/contents/#{material.id}")

      assert destino == ~p"/contents/#{material.id}/3"
      assert {:ok, _view, html} = live(conn, destino)
      assert html =~ "A dobradiça precede o parafuso"
    end

    test "o capítulo está na URL, então a posição é compartilhável", %{
      conn: conn,
      material: material
    } do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/4")

      assert html =~ "Índice remissivo"
      assert html =~ "dobradiça, 2"
    end

    test "carrega um capítulo por vez, não o livro inteiro", %{conn: conn, material: material} do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/2")

      assert html =~ "O parafuso é"
      refute html =~ "A dobradiça precede o parafuso"
    end

    test "material de outro usuário não abre", %{conn: conn} do
      {:ok, outro} =
        QuizProject.Accounts.register_user(
          %{
            email: "outro#{System.unique_integer([:positive])}@teste.com",
            password: "senha12345"
          },
          authorize?: false
        )

      {:ok, alheio} = AdaptiveStudy.create_material(outro, %{title: "Alheio", format: :epub})

      assert {:error, {:live_redirect, %{to: "/contents"}}} =
               live(conn, ~p"/contents/#{alheio.id}")
    end

    test "livro ainda em ingestão mostra o avanço por capítulo", %{conn: conn, user: user} do
      {:ok, chegando} =
        AdaptiveStudy.create_material(user, %{
          title: "Chegando",
          format: :epub,
          status: "ingesting"
        })

      {:ok, view, html} = live(conn, ~p"/contents/#{chegando.id}")

      assert html =~ "ainda está sendo processado"

      Phoenix.PubSub.broadcast(
        QuizProject.PubSub,
        Books.ingest_topic(chegando.id),
        {:ingest_progress, %{material_id: chegando.id, done: 3, total: 12, title: "3 O martelo"}}
      )

      assert render(view) =~ "Capítulo 3 de 12"
      assert render(view) =~ "3 O martelo"
    end

    test "material sem capítulos explica em vez de quebrar", %{conn: conn, user: user} do
      {:ok, texto} =
        AdaptiveStudy.create_material(user, %{title: "Notas", raw_content: "Um parágrafo."})

      {:ok, _view, html} = live(conn, ~p"/contents/#{texto.id}")

      assert html =~ "não é um livro em capítulos"
    end
  end

  describe "renderização dos blocos" do
    setup %{conn: conn, material: material} do
      {:ok, view, html} = live(conn, ~p"/contents/#{material.id}/2")
      %{view: view, html: html}
    end

    test "cada bloco carrega a âncora usada pela posição, busca e filtro", %{html: html} do
      assert html =~ ~s(id="block-2")
      assert html =~ ~s(data-position="2")
    end

    test "a marcação inline vira HTML, não texto cru", %{html: html} do
      assert html =~ "<em>simples</em>"
      assert html =~ "<strong>antigo</strong>"
      assert html =~ "<code>screw</code>"
    end

    test "listagem sai com título, código e anotações", %{html: html} do
      assert html =~ "Listagem 1.1 Medindo o passo da rosca"
      assert html =~ "qreader-annotations"
      assert html =~ "#1 Em milímetros"
      assert html =~ "def passo(voltas, comprimento):"
    end

    test "callout e figura têm marcação própria", %{html: html} do
      assert html =~ "qreader-callout"
      assert html =~ "qreader-figure"
      assert html =~ "Figura 1.1 Corte longitudinal"
    end

    test "a folha da editora entra por rota própria", %{html: html, material: material} do
      assert html =~ ~s|/contents/#{material.id}/book.css|
    end

    test "a figura sai como imagem de verdade, com alt e carga preguiçosa", %{
      html: html,
      material: material
    } do
      assert html =~ ~s|src="/contents/#{material.id}/images/OEBPS/Images/parafuso.png"|
      assert html =~ ~s|alt="Corte de um parafuso"|
      assert html =~ ~s|loading="lazy"|
      refute html =~ "Figura não incluída"
    end
  end

  describe "imagens" do
    test "a imagem no meio da frase também aponta para a rota", %{
      conn: conn,
      material: material
    } do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/3")

      assert html =~ ~s|src="/contents/#{material.id}/images/OEBPS/Images/equacao.png"|
    end

    test "o diagrama transparente é marcado para inverter no tema escuro", %{
      conn: conn,
      material: material
    } do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/2")

      # A navbar tem o próprio logo; só interessam as imagens do livro.
      [diagrama, captura] =
        ~r/<img[^>]+>/
        |> Regex.scan(html)
        |> Enum.map(&hd/1)
        |> Enum.filter(&(&1 =~ "/contents/"))

      assert diagrama =~ "parafuso.png"
      assert diagrama =~ "qreader-invertible"

      # Captura de tela é opaca: inverter produziria um negativo.
      assert captura =~ "captura.png"
      refute captura =~ "qreader-invertible"
    end

    test "a imagem no meio da frase também é marcada", %{conn: conn, material: material} do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/3")

      assert html =~ ~s|equacao.png" class="qreader-invertible"|
    end

    test "serve a imagem com tipo e cache longo", %{conn: conn, material: material} do
      conn = get(conn, ~p"/contents/#{material.id}/images/OEBPS/Images/parafuso.png")

      assert response_content_type(conn, :png) =~ "image/png"
      assert get_resp_header(conn, "cache-control") == ["private, max-age=31536000, immutable"]
      assert response(conn, 200) == EpubFixture.png()
    end

    test "caminho que não é do livro devolve 404", %{conn: conn, material: material} do
      assert conn
             |> get(~p"/contents/#{material.id}/images/OEBPS/Images/inexistente.png")
             |> response(404)
    end

    test "não serve imagem de livro de outro usuário", %{conn: conn, user: user} do
      {:ok, outro} =
        QuizProject.Accounts.register_user(
          %{
            email: "outro#{System.unique_integer([:positive])}@teste.com",
            password: "senha12345"
          },
          authorize?: false
        )

      {:ok, alheio} = AdaptiveStudy.create_material(outro, %{title: "Alheio", format: :epub})
      {:ok, alheio} = Books.ingest(alheio, EpubFixture.build(), outro)

      refute user.id == outro.id

      assert conn
             |> get(~p"/contents/#{alheio.id}/images/OEBPS/Images/parafuso.png")
             |> response(404)
    end

    test "figura sem a imagem no pacote mostra o lugar reservado", %{conn: conn, user: user} do
      {:ok, incompleto} =
        AdaptiveStudy.create_material(user, %{title: "Incompleto", format: :epub})

      {:ok, incompleto} =
        Books.ingest(incompleto, EpubFixture.build(%{"OEBPS/Images/parafuso.png" => nil}), user)

      {:ok, _view, html} = live(conn, ~p"/contents/#{incompleto.id}/2")

      assert html =~ "Figura não incluída"
      refute html =~ "images/OEBPS/Images/parafuso.png"
    end
  end

  describe "sumário" do
    test "começa fora da tela, deixando só o texto", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      assert has_element?(view, "#contents-drawer.-translate-x-full")
      refute has_element?(view, "#contents-backdrop")
    end

    test "o botão da barra traz o painel", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("#open-contents") |> render_click()

      assert has_element?(view, "#contents-drawer.translate-x-0")
      assert has_element?(view, "#contents-backdrop")
    end

    test "escolher um capítulo fecha o painel", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("#open-contents") |> render_click()
      view |> element(~s|aside a[href="/contents/#{material.id}/3"]|) |> render_click()

      assert has_element?(view, "#contents-drawer.-translate-x-full")
      refute has_element?(view, "#contents-backdrop")
    end

    test "o termo buscado sobrevive a fechar e reabrir o painel", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("form[phx-change='search']") |> render_change(%{"term" => "dobradiça"})
      view |> element("#open-contents") |> render_click()

      assert render(view) =~ "dobradiça"
      assert has_element?(view, ~s|input[name="term"][value="dobradiça"]|)
    end
  end

  describe "navegação entre capítulos" do
    test "avança e volta pelo sumário", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      assert view
             |> element(~s|aside a[href="/contents/#{material.id}/3"]|)
             |> render_click()

      assert_patched(view, ~p"/contents/#{material.id}/3")
      assert render(view) =~ "A dobradiça precede"
    end

    test "o primeiro capítulo não oferece anterior", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/1")

      refute has_element?(view, ~s|nav a[href$="/contents/#{material.id}/0"]|)
    end
  end

  describe "posição de leitura" do
    test "o leitor grava onde o usuário parou", %{conn: conn, material: material, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      render_hook(view, "save_position", %{"position" => 5, "offset" => 0.25})

      position = Books.get_position(user.id, material.id)

      assert position.block_position == 5
      assert position.offset == 0.25
    end
  end

  describe "painéis no telefone" do
    test "a aparência é uma folha de baixo, não uma expansão da barra fixa", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      assert has_element?(view, "#appearance-sheet.translate-y-\\[110\\%\\]")
      refute has_element?(view, "#appearance-backdrop")

      view |> element("#open-appearance") |> render_click()

      assert has_element?(view, "#appearance-sheet.translate-y-0")
      assert has_element?(view, "#appearance-backdrop")
    end

    test "ajustar a aparência não fecha a folha", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("#open-appearance") |> render_click()
      view |> element("form[phx-change='appearance']") |> render_change(%{"font_size" => "120"})

      assert has_element?(view, "#appearance-sheet.translate-y-0")
    end

    test "abrir o sumário fecha a aparência, e vice-versa", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("#open-appearance") |> render_click()
      view |> element("#open-contents") |> render_click()

      assert has_element?(view, "#contents-drawer.translate-x-0")
      assert has_element?(view, "#appearance-sheet.translate-y-\\[110\\%\\]")

      view |> element("#open-appearance") |> render_click()

      assert has_element?(view, "#appearance-sheet.translate-y-0")
      assert has_element?(view, "#contents-drawer.-translate-x-full")
    end

    test "a folha fecha pelo próprio botão", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      view |> element("#open-appearance") |> render_click()
      view |> element("#close-appearance") |> render_click()

      assert has_element?(view, "#appearance-sheet.translate-y-\\[110\\%\\]")
      refute has_element?(view, "#appearance-backdrop")
    end
  end

  describe "aparência" do
    test "a escolha vira variável CSS e persiste por usuário", %{
      conn: conn,
      material: material,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      render_click(view, "toggle_appearance")

      html =
        view
        |> element("form[phx-change='appearance']")
        |> render_change(%{
          "font" => "mono",
          "width" => "wide",
          "font_size" => "130",
          "line_height" => "200"
        })

      assert html =~ "--qreader-width: 90ch"
      assert html =~ "--qreader-size: 1.3rem"
      assert html =~ "--qreader-leading: 2.0"

      assert Books.get_preferences(user.id).font == :mono
    end

    test "valor fora da lista não derruba a tela", %{conn: conn, material: material, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      render_click(view, "toggle_appearance")

      view
      |> element("form[phx-change='appearance']")
      |> render_change(%{"font" => "comic-sans", "width" => "gigante"})

      assert Books.get_preferences(user.id).font == :serif
    end
  end

  describe "busca" do
    test "lista as ocorrências com link para o bloco", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"term" => "dobradiça"})

      assert html =~ "ocorrência"
      assert html =~ "/contents/#{material.id}/3#block-"
    end

    test "termo sem resultado avisa em vez de sumir com o sumário", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"term" => "girassóis"})

      assert html =~ "Nada encontrado"
    end
  end

  describe "cobertura do filtro" do
    test "o bloco demarcado sai marcado, sem varrer texto no render", %{
      conn: conn,
      material: material
    } do
      Books.demarcate(material.id, "no_rosca", [3, 4])

      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/2")

      assert html =~ "qreader-covered"
      assert html =~ ~s(data-nodes="no_rosca")
    end

    test "sem demarcação nenhum bloco vem marcado", %{conn: conn, material: material} do
      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/2")

      refute html =~ "qreader-covered"
    end
  end

  describe "curadoria de capítulo por IA" do
    test "o botão dispara o processamento e vira link ao terminar", %{
      conn: conn,
      material: material
    } do
      {:ok, view, html} = live(conn, ~p"/contents/#{material.id}/2")

      {:ok, chapter} = Books.get_chapter(material.id, 2)

      assert has_element?(view, "#chapter-ai-#{chapter.id}")
      refute html =~ "Processando com IA..."

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()
      html = view |> element("#start-curation") |> render_click()

      assert html =~ "Processando com IA..."

      finished = Enum.find(Books.list_chapters(material.id), &(&1.id == chapter.id))
      assert finished.curation_status == :done

      html = render(view)
      assert html =~ ~s|href="/adaptive-study/#{finished.curated_material_id}/curate"|
    end

    test "o botão mostra o tamanho do capítulo, e some com ele ao terminar", %{
      conn: conn,
      material: material
    } do
      {:ok, view, html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      assert chapter.estimated_tokens > 0
      assert html =~ "qreader-tool-count"
      assert has_element?(view, ".qreader-tool-count", to_string(chapter.estimated_tokens))

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()
      view |> element("#start-curation") |> render_click()

      # Processado, o botão vira link para o material gerado: o tamanho do
      # capítulo deixou de ser uma escolha a fazer.
      html = render(view)
      refute html =~ "qreader-tool-count"
    end

    test "capítulo sem blocos não mostra contador zerado", %{conn: conn, material: material} do
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      chapter
      |> Ash.Changeset.for_update(:update, %{estimated_tokens: 0}, authorize?: false)
      |> Ash.update!()

      {:ok, _view, html} = live(conn, ~p"/contents/#{material.id}/2")

      refute html =~ "qreader-tool-count"
    end

    test "clicar de novo depois de pronto não reprocessa", %{
      conn: conn,
      material: material,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()
      view |> element("#start-curation") |> render_click()

      # Já processado, o botão virou link: reprocessar exigiria uma segunda
      # confirmação, e não há botão para abri-la.
      refute has_element?(view, "#chapter-ai-#{chapter.id}[phx-click]")

      materiais_gerados = AdaptiveStudy.list_materials(user) |> Enum.count(&(&1.format == :text))

      assert materiais_gerados == 1
    end

    test "o botão abre a confirmação em vez de processar direto", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      html = view |> element("#chapter-ai-#{chapter.id}") |> render_click()

      assert html =~ "Processar com IA"
      assert has_element?(view, "#curation-dialog")
      refute html =~ "Processando com IA..."

      intocado = Enum.find(Books.list_chapters(material.id), &(&1.id == chapter.id))
      refute intocado.curation_status == :done
    end

    test "a confirmação mostra tamanho, provedor, modelo e custo", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      html = view |> element("#chapter-ai-#{chapter.id}") |> render_click()

      assert html =~ "Entrada"
      assert html =~ "Saída prevista"
      assert html =~ "Janela de entrada"

      # Em teste o provider é o Fake: local, sem modelo e sem custo — e a tela
      # diz isso em vez de mostrar zero.
      assert html =~ "Fake"
      assert has_element?(view, "#curation-cost", "sem custo")
      assert has_element?(view, "#curation-context", "—")

      # O saldo não existe na API de inferência de nenhum provedor; a ausência
      # é dita na tela para não parecer integração quebrada.
      assert html =~ "indisponível"
    end

    test "cancelar fecha a confirmação sem processar", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()
      html = view |> element("#close-curation") |> render_click()

      refute has_element?(view, "#curation-dialog")
      refute html =~ "Processando com IA..."

      intocado = Enum.find(Books.list_chapters(material.id), &(&1.id == chapter.id))
      refute intocado.curation_status == :done
    end

    test "a confirmação deixa escolher provedor e modelo", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()

      # Em teste o provider global é o Fake, e é ele que abre selecionado.
      assert has_element?(view, "#curation-picker option[value=fake][selected]")

      # Os outros provedores continuam na lista mesmo sem chave: dá para
      # comparar preço com quem não está contratado.
      assert has_element?(view, "#curation-picker option[value=claude]")
      assert has_element?(view, "#curation-picker option[value=openai]")
      assert has_element?(view, "#curation-picker option[value=gemini]")

      html =
        view
        |> form("#curation-picker", %{"provider" => "claude", "model" => ""})
        |> render_change()

      # Trocar de provedor troca a lista de modelos e mostra o preço de tabela.
      assert has_element?(view, ~s(#curation-model option[value="claude-opus-5"]))
      refute has_element?(view, ~s(#curation-model option[value="gpt-5.6-sol"]))
      assert html =~ "por Mtok"
      assert has_element?(view, "#curation-price", "US$ 5/25")
      assert has_element?(view, "#curation-cost", "US$")
      assert has_element?(view, "#curation-context", "1.0M")
    end

    test "provedor sem chave mostra o preço mas não processa", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()

      # Duas etapas porque é assim que o formulário se comporta: trocar o
      # provedor é o que traz os modelos dele para o `<select>`.
      view
      |> form("#curation-picker", %{"provider" => "claude", "model" => ""})
      |> render_change()

      view
      |> form("#curation-picker", %{"provider" => "claude", "model" => "claude-opus-5"})
      |> render_change()

      assert has_element?(view, "#curation-unavailable")
      assert has_element?(view, "#start-curation[disabled]")

      # O botão desabilitado é a interface; a garantia é o servidor. Aqui o
      # evento chega direto pelo socket, como chegaria de um cliente adulterado.
      render_click(view, "curate_chapter", %{"id" => chapter.id})

      intocado = Enum.find(Books.list_chapters(material.id), &(&1.id == chapter.id))
      refute intocado.curation_status == :done
    end

    test "combinação que não existe no catálogo é ignorada", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")
      {:ok, chapter} = Books.get_chapter(material.id, 2)

      view |> element("#chapter-ai-#{chapter.id}") |> render_click()

      # Combinação impossível pela tela: provedor local com modelo da OpenAI.
      # Não vira estado, então a tela continua coerente com o que o botão faria.
      render_change(view, "pick_curation", %{"provider" => "fake", "model" => "gpt-5.6-sol"})

      assert has_element?(view, "#curation-picker option[value=fake][selected]")
      refute has_element?(view, ~s(#curation-model option[value="gpt-5.6-sol"]))

      render_change(view, "pick_curation", %{"provider" => "provedor-que-nao-existe"})

      assert has_element?(view, "#curation-picker option[value=fake][selected]")
    end
  end

  describe "mensagens que a rota herda sem pedir" do
    test "notificação de tentativa não derruba o leitor", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/contents/#{material.id}/2")

      send(view.pid, {:attempt_finished, %{attempt_id: Ecto.UUID.generate()}})
      send(view.pid, {:mindmap_generated, %{material_id: material.id}})

      assert render(view) =~ "1 O parafuso"
    end
  end

  describe "folha de estilo do livro" do
    test "serve o CSS filtrado com cache longo", %{conn: conn, material: material} do
      conn = get(conn, ~p"/contents/#{material.id}/book.css")

      assert response_content_type(conn, :css) =~ "text/css"
      assert get_resp_header(conn, "cache-control") == ["private, max-age=31536000, immutable"]

      css = response(conn, 200)
      assert css =~ ".qreader-book"
      refute css =~ "@page"
    end

    test "não serve o livro de outro usuário", %{conn: conn} do
      {:ok, outro} =
        QuizProject.Accounts.register_user(
          %{
            email: "outro#{System.unique_integer([:positive])}@teste.com",
            password: "senha12345"
          },
          authorize?: false
        )

      {:ok, alheio} = AdaptiveStudy.create_material(outro, %{title: "Alheio", format: :epub})

      assert conn |> get(~p"/contents/#{alheio.id}/book.css") |> response(404)
    end
  end
end
