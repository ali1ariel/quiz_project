defmodule QuizProjectWeb.AdaptiveStudyLive.CurateBookTest do
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
    {:ok, chapter} = Books.get_chapter(material.id, 2)
    {:ok, _} = Books.curate_chapter_async(chapter, user)

    curated =
      chapter.material_id
      |> Books.list_chapters()
      |> Enum.find(&(&1.id == chapter.id))

    {:ok, curated_material} = AdaptiveStudy.get_material(curated.curated_material_id, user)

    %{book_material: material, curated_material: curated_material}
  end

  test "o nó folha selecionado mostra trecho não vazio resolvido dos blocos", %{
    conn: conn,
    curated_material: curated_material
  } do
    {:ok, view, _html} = live(conn, ~p"/study/#{curated_material.id}/curate")

    leaf =
      curated_material.mindmap_tree["nodes"]
      |> AdaptiveStudy.flatten_nodes()
      |> Enum.find(&(&1["children"] in [[], nil]))

    assert (leaf["content"] || "") == ""

    html =
      view
      |> element("#tree-node-#{leaf["id"]}")
      |> render_click()

    refute html =~ "Este nó não carrega trecho de texto"
  end

  test "o trecho resolvido de um nó que cobre uma figura mostra a imagem, não só a legenda", %{
    conn: conn,
    book_material: book_material,
    curated_material: curated_material
  } do
    {:ok, chapter} = Books.get_chapter(book_material.id, 2)

    figura =
      chapter.id
      |> Books.list_blocks()
      |> Enum.find(&(&1.type == :figure and &1.image_path != nil))

    [node_id | _] = Map.fetch!(Books.coverage(chapter.id), figura.id)

    {:ok, view, _html} = live(conn, ~p"/study/#{curated_material.id}/curate")

    html = view |> element("#tree-node-#{node_id}") |> render_click()

    assert html =~ ~s(src="/contents/#{book_material.id}/images/#{figura.image_path}")
    assert html =~ figura.content
  end

  test "a edição do nó não oferece campo de content para material de livro", %{
    conn: conn,
    curated_material: curated_material
  } do
    {:ok, view, _html} = live(conn, ~p"/study/#{curated_material.id}/curate")

    html =
      view
      |> element("#node-detail-panel button[title='Editar nó']")
      |> render_click()

    refute html =~ ~s(name="content")
    assert html =~ "não é editável aqui"
  end
end
