defmodule QuizProjectWeb.ContentsLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.EpubFixture

  setup :register_and_log_in_user

  defp book(user, attrs \\ %{}) do
    {:ok, book} =
      AdaptiveStudy.create_material(
        user,
        Map.merge(%{title: "Processando livro...", format: :epub, status: "ingesting"}, attrs)
      )

    book
  end

  defp ingested(user) do
    {:ok, book} = Books.ingest(book(user), EpubFixture.build(), user)
    book
  end

  describe "biblioteca" do
    test "vazia convida a adicionar o primeiro livro", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "Nenhum livro na biblioteca"
      assert html =~ ~p"/contents/new"
    end

    test "lista o livro com autor e total de capítulos", %{conn: conn, user: user} do
      livro = ingested(user)

      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "Tratado das Coisas Pequenas"
      assert html =~ "Ana Ribeiro"
      assert html =~ "4 capítulos"
      assert html =~ ~p"/contents/#{livro.id}"
    end

    test "material de texto não aparece na biblioteca", %{conn: conn, user: user} do
      {:ok, _texto} =
        AdaptiveStudy.create_material(user, %{title: "Notas de aula", raw_content: "Um texto."})

      {:ok, _view, html} = live(conn, ~p"/contents")

      refute html =~ "Notas de aula"
      assert html =~ "Nenhum livro na biblioteca"
    end

    test "livro já aberto mostra onde parou e convida a continuar", %{conn: conn, user: user} do
      livro = ingested(user)
      {:ok, chapter} = Books.get_chapter(livro.id, 3)

      {:ok, _} =
        Books.save_position(user.id, livro.id, %{
          chapter_id: chapter.id,
          block_position: 20,
          offset: 0.5
        })

      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "Capítulo 3 de 4"
      assert html =~ "Continuar"
      refute html =~ ">Ler"
    end

    test "livro em ingestão avisa que ainda está sendo lido", %{conn: conn, user: user} do
      book(user, %{title: "Chegando"})

      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "Chegando"
      assert html =~ "Lendo o livro..."
    end

    test "livro recusado mostra o motivo no cartão", %{conn: conn, user: user} do
      {:error, :drm_protected} = Books.ingest(book(user), EpubFixture.build_drm(), user)

      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "DRM"
    end

    test "a conclusão da ingestão atualiza a lista sozinha", %{conn: conn, user: user} do
      chegando = book(user, %{title: "Chegando"})

      {:ok, view, _html} = live(conn, ~p"/contents")
      assert render(view) =~ "Lendo o livro..."

      {:ok, _} = Books.ingest(chegando, EpubFixture.build(), user)
      send(view.pid, {:ingest_finished, %{material_id: chegando.id, result: :ok}})

      refute render(view) =~ "Lendo o livro..."
      assert render(view) =~ "4 capítulos"
    end

    test "remove o livro da biblioteca", %{conn: conn, user: user} do
      livro = ingested(user)

      {:ok, view, _html} = live(conn, ~p"/contents")

      html = view |> element("#delete-book-#{livro.id}") |> render_click()

      assert html =~ "Nenhum livro na biblioteca"
      assert AdaptiveStudy.list_books(user) == []
    end

    test "não lista livro de outro usuário", %{conn: conn} do
      {:ok, outro} =
        QuizProject.Accounts.register_user(
          %{
            email: "outro#{System.unique_integer([:positive])}@teste.com",
            password: "senha12345"
          },
          authorize?: false
        )

      ingested(outro)

      {:ok, _view, html} = live(conn, ~p"/contents")

      assert html =~ "Nenhum livro na biblioteca"
    end
  end

  describe "adicionar livro" do
    test "ingere o EPUB e volta para a biblioteca", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/new")

      enviar(view, EpubFixture.build(), "tratado.epub")

      assert_redirect(view, ~p"/contents")

      assert [livro] = AdaptiveStudy.list_books(user)
      assert livro.title == "Tratado das Coisas Pequenas"
      assert length(Books.list_chapters(livro.id)) == 4
    end

    test "o título digitado vence o do próprio livro", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/new")

      enviar(view, EpubFixture.build(), "tratado.epub", "Meu apelido para o livro")

      assert [livro] = AdaptiveStudy.list_books(user)
      assert livro.title == "Meu apelido para o livro"
    end

    test "recusa DRM na tela, sem criar livro nenhum", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/new")

      html = enviar(view, EpubFixture.build_drm(), "protegido.epub")

      assert html =~ "protegido por DRM"
      assert AdaptiveStudy.list_books(user) == []
    end

    test "recusa layout fixo na tela", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/new")

      html = enviar(view, EpubFixture.build_fixed_layout(), "quadrinho.epub")

      assert html =~ "layout fixo"
      assert AdaptiveStudy.list_books(user) == []
    end

    test "recusa arquivo que não é EPUB", %{conn: conn, user: user} do
      {:ok, {_name, zip}} = :zip.create(~c"x.zip", [{~c"leia.txt", "oi"}], [:memory])

      {:ok, view, _html} = live(conn, ~p"/contents/new")

      html = enviar(view, zip, "disfarcado.epub")

      assert html =~ "não é um EPUB válido"
      assert AdaptiveStudy.list_books(user) == []
    end

    test "enviar sem escolher arquivo avisa em vez de criar vazio", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/contents/new")

      html = render_submit(view, "save", %{"title" => ""})

      assert html =~ "Escolha um arquivo .epub"
      assert AdaptiveStudy.list_books(user) == []
    end

    test "o campo aceita só .epub", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contents/new")

      assert html =~ ~s(accept=".epub")
      assert html =~ "Até 80 MB"
    end
  end

  defp enviar(view, binary, name, title \\ "") do
    entrada =
      file_input(view, "#upload-book-form", :book, [
        %{name: name, content: binary, type: "application/epub+zip"}
      ])

    render_upload(entrada, name)
    render_submit(view, "save", %{"title" => title})
  end
end
