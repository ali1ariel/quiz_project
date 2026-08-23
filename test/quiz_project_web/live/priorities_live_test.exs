defmodule QuizProjectWeb.PrioritiesLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.AdaptiveStudy
  alias QuizProject.Priorities

  setup :register_and_log_in_user

  defp category(user, name \\ "Categoria") do
    {:ok, category} = Priorities.create_category(user, %{name: name})
    category
  end

  defp book(user, title) do
    {:ok, book} =
      AdaptiveStudy.create_material(user, %{title: title, format: :epub, status: "draft"})

    book
  end

  defp manual_item(user, category, title \\ "Item") do
    {:ok, item} = Priorities.create_item(user, category, %{item_type: :manual, title: title})
    item
  end

  describe "Index" do
    test "vazio convida a criar a primeira categoria", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/priorities")

      assert html =~ "Nenhuma categoria ainda"
    end

    test "cria categoria pelo formulário inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/priorities")

      view |> element("#new-category-btn") |> render_click()
      html = render_submit(view, "create_category", %{"name" => "Livros"})

      assert html =~ "Livros"
    end

    test "cria item manual dentro de uma categoria", %{conn: conn, user: user} do
      cat = category(user, "Metas")
      {:ok, view, _html} = live(conn, ~p"/priorities")

      render_click(view, "toggle_item_form", %{"category_id" => cat.id})

      html =
        render_submit(view, "create_item", %{
          "category_id" => cat.id,
          "item_type" => "manual",
          "title" => "Beber água"
        })

      assert html =~ "Beber água"
    end

    test "item de livro sem título usa o título do livro escolhido", %{conn: conn, user: user} do
      cat = category(user, "Livros")
      livro = book(user, "Duna")
      {:ok, view, _html} = live(conn, ~p"/priorities")

      render_click(view, "toggle_item_form", %{"category_id" => cat.id})

      html =
        render_submit(view, "create_item", %{
          "category_id" => cat.id,
          "item_type" => "book",
          "title" => "",
          "study_material_id" => livro.id
        })

      assert html =~ "Duna"
    end

    test "excluir remove item da listagem definitivamente", %{conn: conn, user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Descartável")
      {:ok, view, html} = live(conn, ~p"/priorities")

      assert html =~ "Descartável"

      render_click(view, "open_item", %{"id" => item.id})
      view |> element("#delete-item-btn") |> render_click()

      refute render(view) =~ "Descartável"
      assert {:error, _} = Priorities.get_item(item.id, user)
    end

    test "reordenar itens por drag-and-drop grava a nova posição", %{conn: conn, user: user} do
      cat = category(user)
      first = manual_item(user, cat, "Primeiro")
      second = manual_item(user, cat, "Segundo")
      {:ok, view, _html} = live(conn, ~p"/priorities")

      render_change(view, "reorder_items", %{
        "zone_id" => cat.id,
        "ordered_ids" => [second.id, first.id]
      })

      reordered = Priorities.list_primary_items(cat.id)
      assert Enum.map(reordered, & &1.id) == [second.id, first.id]
    end

    test "reordenar categorias por drag-and-drop grava a nova posição", %{conn: conn, user: user} do
      first = category(user, "Primeira")
      second = category(user, "Segunda")
      {:ok, view, _html} = live(conn, ~p"/priorities")

      render_change(view, "reorder_categories", %{"ordered_ids" => [second.id, first.id]})

      assert Enum.map(Priorities.list_categories(user), & &1.id) == [second.id, first.id]
    end

    test "abrir um item mostra o modal sem navegar; fechar recarrega a lista", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      item = manual_item(user, cat, "Editável")
      {:ok, view, _html} = live(conn, ~p"/priorities")

      html = render_click(view, "open_item", %{"id" => item.id})
      assert html =~ "modal-open"
      assert html =~ "Editável"

      html = render_click(view, "close_item_modal", %{})
      refute html =~ "modal-open"
    end
  end

  describe "Show" do
    # A partir daqui os eventos são tratados pelo `ItemModal` (um
    # `Phoenix.LiveComponent`, `standalone={true}` nesta rota), não mais pela
    # LiveView `Show` diretamente — por isso os testes disparam via seletor de
    # DOM (`element`/`form`), que resolve o `phx-target` certo, em vez de
    # `render_click(view, "evento", ...)` direto na view.
    test "checklist: adicionar subtarefa e marcar reflete no progresso", %{conn: conn, user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :checklist, title: "Lista"})

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      view |> form("#create-task-form", %{"title" => "Passo 1"}) |> render_submit()
      html = view |> form("#create-task-form", %{"title" => "Passo 2"}) |> render_submit()

      assert html =~ "Passo 1"
      assert html =~ "Passo 2"

      task = Priorities.list_tasks(item.id) |> List.first()
      html = view |> element("#toggle-task-#{task.id}") |> render_click()

      assert html =~ "50%"
    end

    test "hábito: marcar hoje incrementa e persiste depois de recarregar", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :habit, title: "Meditar"})

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      html = view |> element("#check-in-habit-btn") |> render_click()
      assert html =~ "1 dia seguido"

      {:ok, _view2, html2} = live(conn, ~p"/priorities/#{item.id}")
      assert html2 =~ "1 dia seguido"
    end

    test "tags: adicionar e remover", %{conn: conn, user: user} do
      cat = category(user)
      item = manual_item(user, cat)

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      html = view |> form("#add-tag-form", %{"name" => "importante"}) |> render_submit()
      assert html =~ "importante"

      tag = Priorities.list_tags(user) |> List.first()
      html = view |> element("#remove-tag-#{tag.id}") |> render_click()
      refute html =~ "importante"
    end

    test "categoria secundária: associar torna o item visível nas duas categorias", %{
      conn: conn,
      user: user
    } do
      primaria = category(user, "Primária")
      secundaria = category(user, "Secundária")
      item = manual_item(user, primaria, "Compartilhado")

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      view
      |> form("#add-secondary-category-form", %{"category_id" => secundaria.id})
      |> render_submit()

      assert Enum.map(Priorities.list_items_by_category(secundaria.id), & &1.id) == [item.id]
    end

    test "campo customizado: criar e salvar valor", %{conn: conn, user: user} do
      cat = category(user)
      item = manual_item(user, cat)

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      view |> element("#toggle-new-field-form-btn") |> render_click()

      view
      |> form("#new-field-form", %{"name" => "Nota", "field_type" => "number"})
      |> render_submit()

      definition = Priorities.list_field_definitions(user) |> List.first()

      html =
        view
        |> form("#set-field-value-#{definition.id}", %{"value" => "8"})
        |> render_submit()

      assert html =~ "Nota"
    end

    test "tier: escolher pelo radio grava e desmarcar volta pra sem tier", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      item = manual_item(user, cat)

      {:ok, view, _html} = live(conn, ~p"/priorities/#{item.id}")

      view |> form("#tier-form", %{"tier" => "A"}) |> render_change()
      assert Priorities.get_item(item.id, user) |> elem(1) |> Map.get(:tier) == :A

      view |> form("#tier-form", %{"tier" => ""}) |> render_change()
      assert Priorities.get_item(item.id, user) |> elem(1) |> Map.get(:tier) == nil
    end

    test "manual: alterna entre percentual e etapas, e o modo persiste ao recarregar", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      item = manual_item(user, cat)

      {:ok, view, html} = live(conn, ~p"/priorities/#{item.id}")
      assert html =~ "manual-percent-form"
      refute html =~ "manual-steps-form"

      html = view |> element("button", "Etapas") |> render_click()
      assert html =~ "manual-steps-form"
      refute html =~ "manual-percent-form"

      html =
        view
        |> form("#manual-steps-form", %{"manual_completed_steps" => "3", "manual_total_steps" => "4"})
        |> render_submit()

      assert html =~ "75%"
      assert Priorities.progress_for_item(Priorities.get_item(item.id, user) |> elem(1)) ==
               {:percent, 75}

      {:ok, view2, html2} = live(conn, ~p"/priorities/#{item.id}")
      assert html2 =~ "manual-steps-form"
      assert html2 =~ "75%"

      html2 = view2 |> element("button", "Percentual") |> render_click()
      assert html2 =~ ~s(value="75")

      html2 =
        view2
        |> form("#manual-percent-form", %{"manual_percent" => "10"})
        |> render_submit()

      assert html2 =~ "10%"
      assert Priorities.progress_for_item(Priorities.get_item(item.id, user) |> elem(1)) ==
               {:percent, 10}
    end

    test "item de outro usuário redireciona com aviso", %{conn: conn} do
      {:ok, other} =
        QuizProject.Accounts.register_user(%{email: "outra@teste.com", password: "senha12345"},
          authorize?: false
        )

      cat = category(other)
      item = manual_item(other, cat)

      assert {:error, {:live_redirect, %{to: "/priorities"}}} =
               live(conn, ~p"/priorities/#{item.id}")
    end
  end

  describe "Ranking" do
    test "definir tier agrupa o item na faixa certa", %{conn: conn, user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Prioridade máxima")

      {:ok, view, html} = live(conn, ~p"/priorities/ranking")
      assert html =~ "Sem tier"

      render_change(view, "set_tier", %{"id" => item.id, "value" => "S"})

      assert Priorities.list_tiered_items(user) |> Keyword.get(:S) |> Enum.map(& &1.id) == [
               item.id
             ]
    end
  end

  describe "Browse" do
    test "filtra por tag", %{conn: conn, user: user} do
      cat = category(user)
      item1 = manual_item(user, cat, "Com tag")
      _item2 = manual_item(user, cat, "Sem tag")

      {:ok, tag} = Priorities.find_or_create_tag(user, "foco")
      {:ok, _} = Priorities.add_tag_to_item(item1, tag, user)

      {:ok, view, _html} = live(conn, ~p"/priorities/items")

      html = render_change(view, "filter", %{"tag_id" => tag.id})

      assert html =~ "Com tag"
      refute html =~ "Sem tag"
    end
  end
end
