defmodule QuizProjectWeb.KanbanLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Priorities

  setup :register_and_log_in_user

  defp category(user, name \\ "Categoria") do
    {:ok, category} = Priorities.create_category(user, %{name: name})
    category
  end

  defp manual_item(user, category, title) do
    {:ok, item} = Priorities.create_item(user, category, %{item_type: :manual, title: title})
    item
  end

  defp activity(user, item, title, attrs \\ %{}) do
    {:ok, activity} =
      Priorities.create_activity(user, Map.merge(%{title: title, item_id: item.id}, attrs))

    activity
  end

  defp loose_activity(user, title, attrs \\ %{}) do
    {:ok, activity} = Priorities.create_activity(user, Map.merge(%{title: title}, attrs))
    activity
  end

  describe "raias" do
    test "só aparece item com atividade de hoje, mesmo com pendência de ontem", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      item = manual_item(user, cat, "Estudar Elixir")
      activity(user, item, "Hoje")
      activity(user, item, "Ontem", %{logical_date: Date.add(Date.utc_today(), -1)})

      other_item = manual_item(user, cat, "Sem nada hoje")
      activity(user, other_item, "Só ontem", %{logical_date: Date.add(Date.utc_today(), -1)})

      {:ok, _view, html} = live(conn, ~p"/today")

      assert html =~ "Estudar Elixir"
      refute html =~ "Sem nada hoje"
    end

    test "raia sem atividade hoje não aparece de jeito nenhum", %{conn: conn, user: user} do
      manual_item(user, category(user), "Item ocioso")

      {:ok, _view, html} = live(conn, ~p"/today")

      refute html =~ "Item ocioso"
    end
  end

  describe "fluxo" do
    test "move_flow leva atividade de todo pra fazendo e volta", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Escrever spec")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_click(view, "move_flow", %{"id" => act.id, "value" => "fazendo"})
      assert Priorities.get_activity(act.id, user) |> elem(1) |> Map.get(:flow) == :fazendo

      render_click(view, "move_flow", %{"id" => act.id, "value" => "todo"})
      assert Priorities.get_activity(act.id, user) |> elem(1) |> Map.get(:flow) == :todo
    end

    test "sem limite de WIP: duas atividades podem ir pra fazendo ao mesmo tempo", %{
      conn: conn,
      user: user
    } do
      item = manual_item(user, category(user), "Projeto")
      a = activity(user, item, "A")
      b = activity(user, item, "B")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_click(view, "move_flow", %{"id" => a.id, "value" => "fazendo"})
      html = render_click(view, "move_flow", %{"id" => b.id, "value" => "fazendo"})

      assert Priorities.get_activity(a.id, user) |> elem(1) |> Map.get(:flow) == :fazendo
      assert Priorities.get_activity(b.id, user) |> elem(1) |> Map.get(:flow) == :fazendo
      assert html =~ "A"
      assert html =~ "B"
    end

    test "complete_activity move pra coluna feito", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Terminar isso")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_click(view, "complete_activity", %{"id" => act.id})

      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.status == :concluida
      assert updated.flow == :feito
    end
  end

  describe "capturas soltas" do
    test "aparecem destacadas no topo, independente da data", %{conn: conn, user: user} do
      loose_activity(user, "Comprar pão")
      loose_activity(user, "Antiga", %{logical_date: Date.add(Date.utc_today(), -10)})

      {:ok, _view, html} = live(conn, ~p"/today")

      document = LazyHTML.from_fragment(html)
      loose_section = LazyHTML.query(document, "#loose-captures")

      assert loose_section |> LazyHTML.text() =~ "Comprar pão"
      assert loose_section |> LazyHTML.text() =~ "Antiga"
    end

    test "create_capture cria uma nova captura solta", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/today")

      html = render_submit(view, "create_capture", %{"title" => "Ligar pro dentista"})

      assert html =~ "Ligar pro dentista"
      assert [%{item_id: nil}] = Priorities.list_loose_captures(user)
    end

    test "create_capture com categoria prende a atividade no item Geral dela, não fica solta", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Livros")
      {:ok, view, _html} = live(conn, ~p"/today")

      html =
        render_submit(view, "create_capture", %{
          "title" => "Ler página 40",
          "category_id" => cat.id
        })

      assert html =~ "Livros - Geral"
      assert Priorities.list_loose_captures(user) == []

      geral = Priorities.general_item_for_category(cat)
      [activity] = Priorities.list_activities_for_item(geral.id, user)
      assert activity.title == "Ler página 40"
    end

    test "triagem por categoria associa a captura ao Geral dela, sem virar prioridade", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Hábitos")
      act = loose_activity(user, "Beber água")

      {:ok, view, html} = live(conn, ~p"/today")
      assert html =~ "Hábitos"

      render_click(view, "assign_category", %{"activity_id" => act.id, "category_id" => cat.id})

      geral = Priorities.general_item_for_category(cat)
      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.item_id == geral.id
      assert Priorities.list_loose_captures(user) == []
    end

    test "concluir e associar a uma prioridade convivem com o mesmo peso visual", %{
      conn: conn,
      user: user
    } do
      manual_item(user, category(user), "Estudar Elixir")
      act = loose_activity(user, "revisar Elixir")

      {:ok, view, html} = live(conn, ~p"/today")

      document = LazyHTML.from_fragment(html)
      card = LazyHTML.query(document, "#activity-card-#{act.id}")
      card_html = LazyHTML.to_html(card)

      assert card_html =~ "Concluir"
      assert card_html =~ "Estudar Elixir"
      assert card_html =~ "btn-success"
      assert card_html =~ "btn-soft"

      render_click(view, "assign_item", %{
        "activity_id" => act.id,
        "item_id" => Priorities.list_loose_captures(user) |> hd() |> Map.get(:id)
      })
    end

    test "triagem em um toque associa a captura ao item sugerido", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Estudar Elixir")
      act = loose_activity(user, "revisar Elixir hoje")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_click(view, "assign_item", %{"activity_id" => act.id, "item_id" => item.id})

      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.item_id == item.id
      assert Priorities.list_loose_captures(user) == []
    end

    test "alerta por idade: urgente com 8 dias, atenção com 4, nada com hoje", %{
      conn: conn,
      user: user
    } do
      urgente = loose_activity(user, "Urgente", %{logical_date: Date.add(Date.utc_today(), -8)})
      atencao = loose_activity(user, "Atenção", %{logical_date: Date.add(Date.utc_today(), -4)})
      hoje = loose_activity(user, "De hoje")

      {:ok, _view, html} = live(conn, ~p"/today")
      document = LazyHTML.from_fragment(html)

      urgente_html =
        LazyHTML.query(document, "#activity-card-#{urgente.id}") |> LazyHTML.to_html()

      atencao_html =
        LazyHTML.query(document, "#activity-card-#{atencao.id}") |> LazyHTML.to_html()

      hoje_html = LazyHTML.query(document, "#activity-card-#{hoje.id}") |> LazyHTML.to_html()

      assert urgente_html =~ "8 dias"
      assert atencao_html =~ "4 dias"
      refute hoje_html =~ "dia"
    end
  end

  describe "detalhe da atividade" do
    test "clicar no título abre o modal com descrição e checklist", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Escrever spec")

      {:ok, view, _html} = live(conn, ~p"/today")

      html = render_click(view, "open_activity", %{"id" => act.id})

      assert html =~ "update-activity-form"
      assert html =~ "Checklist"
      assert html =~ "Nenhum subitem ainda."
    end

    test "update_activity salva título e descrição", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Escrever spec")

      {:ok, view, _html} = live(conn, ~p"/today")
      render_click(view, "open_activity", %{"id" => act.id})

      html =
        view
        |> element("#update-activity-form")
        |> render_submit(%{"title" => "Escrever spec v2", "notes" => "cobrir casos de borda"})

      assert html =~ "Escrever spec v2"

      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.title == "Escrever spec v2"
      assert updated.notes == "cobrir casos de borda"
    end

    test "checklist: criar, marcar e excluir subitem", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Escrever spec")

      {:ok, view, _html} = live(conn, ~p"/today")
      render_click(view, "open_activity", %{"id" => act.id})

      html =
        view
        |> element("#create-activity-task-form")
        |> render_submit(%{"title" => "Revisar exemplos"})

      assert html =~ "Revisar exemplos"
      [task] = Priorities.list_activity_tasks(act.id)
      refute task.done

      html = view |> element("#toggle-activity-task-#{task.id}") |> render_click()
      assert html =~ "line-through"
      [marcado] = Priorities.list_activity_tasks(act.id)
      assert marcado.done

      view |> element("#delete-activity-task-#{task.id}") |> render_click()
      assert Priorities.list_activity_tasks(act.id) == []
    end

    test "close_activity_modal fecha o modal", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Escrever spec")

      {:ok, view, _html} = live(conn, ~p"/today")
      render_click(view, "open_activity", %{"id" => act.id})

      html = render_click(view, "close_activity_modal", %{})

      refute html =~ "update-activity-form"
    end
  end

  describe "hábitos" do
    test "hábito diário aparece como raia ao abrir /today (instância criada sob demanda)", %{
      conn: conn,
      user: user
    } do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :habit, title: "Meditar"})

      {:ok, _view, html} = live(conn, ~p"/today")

      assert html =~ "Meditar"
      [activity] = Priorities.list_activities_for_item(item.id, user)
      assert activity.logical_date == Date.utc_today()
    end

    test "hábito semanal fora do dia devido não aparece como raia", %{conn: conn, user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :habit, title: "Academia"})

      hoje_semana = Date.day_of_week(Date.utc_today())
      outro_dia = if hoje_semana == 1, do: 2, else: 1

      {:ok, _} =
        Priorities.set_habit_frequency(item, %{frequency: :weekly, weekdays: [outro_dia]}, user)

      {:ok, _view, html} = live(conn, ~p"/today")

      refute html =~ "Academia"
      assert Priorities.list_activities_for_item(item.id, user) == []
    end
  end

  describe "badge global" do
    test "contagem de capturas soltas aparece na navbar em outra tela", %{conn: conn, user: user} do
      loose_activity(user, "Solta 1")
      loose_activity(user, "Solta 2")

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      document = LazyHTML.from_fragment(html)

      assert LazyHTML.query(document, "#desktop-nav-kanban") |> LazyHTML.text() =~ "2"
    end
  end
end
