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

  # Hábito é sempre extensão de uma prioridade — atalho pra testes que não
  # se importam com qual prioridade, só que exista uma.
  defp habit_item(user), do: manual_item(user, category(user), "Prioridade")

  defp activity(user, item, title, attrs \\ %{}) do
    {:ok, activity} =
      Priorities.create_activity(user, Map.merge(%{title: title, item_id: item.id}, attrs))

    activity
  end

  defp loose_activity(user, title, attrs \\ %{}) do
    {:ok, activity} = Priorities.create_activity(user, Map.merge(%{title: title}, attrs))
    activity
  end

  describe "board do dia" do
    test "atividade presa a item continua aparecendo mesmo depois de virar o dia — só hábito expira",
         %{conn: conn, user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Estudar Elixir")
      activity(user, item, "Ler capítulo 3")

      activity(user, item, "Revisar exercícios de ontem", %{
        logical_date: Date.add(Date.utc_today(), -1)
      })

      other_item = manual_item(user, cat, "Sem nada hoje")

      activity(user, other_item, "Atividade só de ontem", %{
        logical_date: Date.add(Date.utc_today(), -1)
      })

      {:ok, _view, html} = live(conn, ~p"/today")

      assert html =~ "Ler capítulo 3"
      assert html =~ "Revisar exercícios de ontem"
      assert html =~ "Atividade só de ontem"
    end

    test "atividade resolvida em dia anterior não volta a aparecer na coluna feito hoje", %{
      conn: conn,
      user: user
    } do
      item = manual_item(user, category(user), "Item")
      old = activity(user, item, "Resolvida ontem")
      {:ok, old} = Priorities.complete_activity(old, user)

      old
      |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attribute(:resolved_date, Date.add(Date.utc_today(), -1))
      |> Ash.update!()

      {:ok, _view, html} = live(conn, ~p"/today")

      refute html =~ "Resolvida ontem"
    end

    test "sem nenhuma atividade mostra o estado vazio", %{conn: conn, user: user} do
      _item = manual_item(user, category(user), "Item ocioso")

      {:ok, _view, html} = live(conn, ~p"/today")

      assert html =~ "Nenhuma atividade presa a uma prioridade hoje."
    end

    test "card mostra a lateral colorida da categoria e a badge com o nome da prioridade", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Corpo")
      item = manual_item(user, cat, "Academia")
      act = activity(user, item, "Treino de perna")

      {:ok, _view, html} = live(conn, ~p"/today")

      document = LazyHTML.from_fragment(html)
      card = LazyHTML.query(document, "#activity-card-#{act.id}")
      card_html = LazyHTML.to_html(card)

      assert card_html =~ "Academia"
      refute card_html =~ "Corpo"
      assert card_html =~ "border-left"
    end

    test "captura anexada só à categoria (item Geral) mostra a cor mas nenhuma badge", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Corpo")
      geral = Priorities.general_item_for_category(cat)
      act = activity(user, geral, "Alongar")

      {:ok, _view, html} = live(conn, ~p"/today")

      document = LazyHTML.from_fragment(html)
      card = LazyHTML.query(document, "#activity-card-#{act.id}")
      card_html = LazyHTML.to_html(card)

      assert card_html =~ "border-left"
      refute card_html =~ "Corpo"
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

    test "reopen_activity num card de Feito volta pra a fazer, pra desfazer conclusão por engano",
         %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Projeto")
      act = activity(user, item, "Terminar isso")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_click(view, "complete_activity", %{"id" => act.id})
      html = render_click(view, "reopen_activity", %{"id" => act.id})

      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.status == :pendente
      assert updated.flow == :todo

      document = LazyHTML.from_fragment(html)
      card = LazyHTML.query(document, "#activity-card-#{act.id}")
      assert LazyHTML.to_html(card) =~ "Terminar isso"
    end
  end

  describe "adiar" do
    test "botão Adiar abre o modal com o título da atividade", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Trabalho")
      act = activity(user, item, "Relatório")

      {:ok, view, _html} = live(conn, ~p"/today")
      html = render_click(view, "open_snooze", %{"id" => act.id})

      assert html =~ "Adiar atividade"
      assert html =~ "Relatório"
    end

    test "confirmar o adiamento tira a atividade da tela do dia", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Trabalho")
      act = activity(user, item, "Relatório")
      segunda = Date.add(Date.utc_today(), 3)

      {:ok, view, _html} = live(conn, ~p"/today")
      render_click(view, "open_snooze", %{"id" => act.id})

      html =
        view
        |> element("#snooze-form")
        |> render_submit(%{"until" => Date.to_iso8601(segunda)})

      refute html =~ "Relatório"
      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.snoozed_until == segunda
    end

    test "hábito não mostra o botão Adiar", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      {:ok, view, _html} = live(conn, ~p"/today")

      refute has_element?(view, "button[phx-click='open_snooze']")
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

    test "create_capture com type evento cria uma atividade do tipo evento com a data escolhida",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/today")
      data = Date.add(Date.utc_today(), 4)

      render_submit(view, "create_capture", %{
        "title" => "Consulta médica",
        "type" => "evento",
        "event_date" => Date.to_iso8601(data)
      })

      assert [%{kind: :evento, logical_date: ^data}] = Priorities.list_loose_captures(user)
    end

    test "concluir uma captura solta some de Capturas soltas mas aparece em Feito", %{
      conn: conn,
      user: user
    } do
      act = loose_activity(user, "Comprar leite")

      {:ok, view, _html} = live(conn, ~p"/today")

      html = render_click(view, "complete_activity", %{"id" => act.id})

      document = LazyHTML.from_fragment(html)
      loose_section = LazyHTML.query(document, "#loose-captures")
      refute LazyHTML.text(loose_section) =~ "Comprar leite"

      assert html =~ "Comprar leite"
      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.flow == :feito
    end

    test "descartar uma captura solta some de Capturas soltas mas aparece em Feito", %{
      conn: conn,
      user: user
    } do
      act = loose_activity(user, "Ideia aleatória")

      {:ok, view, _html} = live(conn, ~p"/today")

      html = render_click(view, "discard_activity", %{"id" => act.id})

      document = LazyHTML.from_fragment(html)
      loose_section = LazyHTML.query(document, "#loose-captures")
      refute LazyHTML.text(loose_section) =~ "Ideia aleatória"

      assert html =~ "Ideia aleatória"
      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert updated.status == :descartada
      assert updated.flow == :feito
    end

    test "create_capture com categoria prende a atividade no item Geral dela, não fica solta", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Livros")
      geral = Priorities.general_item_for_category(cat)
      {:ok, view, _html} = live(conn, ~p"/today")

      html =
        render_submit(view, "create_capture", %{
          "title" => "Ler página 40",
          "item_id" => geral.id
        })

      assert html =~ "Ler página 40"
      assert html =~ "Livros"
      assert Priorities.list_loose_captures(user) == []

      [activity] = Priorities.list_activities_for_item(geral.id, user)
      assert activity.title == "Ler página 40"
    end

    test "triagem por categoria associa a captura ao Geral dela, sem virar prioridade", %{
      conn: conn,
      user: user
    } do
      cat = category(user, "Hábitos")
      act = loose_activity(user, "Beber água")
      geral = Priorities.general_item_for_category(cat)

      {:ok, view, html} = live(conn, ~p"/today")
      assert html =~ "Hábitos"

      render_change(view, "attach_category_change", %{
        "activity_id" => act.id,
        "category_id" => cat.id
      })

      render_change(view, "attach_capture", %{"activity_id" => act.id, "item_id" => geral.id})

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

      {:ok, _view, html} = live(conn, ~p"/today")

      document = LazyHTML.from_fragment(html)
      card = LazyHTML.query(document, "#activity-card-#{act.id}")
      card_html = LazyHTML.to_html(card)

      assert card_html =~ "Concluir"
      assert card_html =~ "btn-success"
      assert card_html =~ "Anexar a..."
    end

    test "triagem em um toque associa a captura ao item escolhido", %{conn: conn, user: user} do
      cat = category(user, "Estudos")
      item = manual_item(user, cat, "Estudar Elixir")
      act = loose_activity(user, "revisar Elixir hoje")

      {:ok, view, _html} = live(conn, ~p"/today")

      render_change(view, "attach_category_change", %{
        "activity_id" => act.id,
        "category_id" => cat.id
      })

      render_change(view, "attach_capture", %{"activity_id" => act.id, "item_id" => item.id})

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
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      {:ok, _view, html} = live(conn, ~p"/today")

      assert html =~ "Meditar"

      [activity] =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      assert activity.logical_date == Date.utc_today()
    end

    test "hábito semanal fora do dia devido não aparece como raia", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      hoje_semana = Date.day_of_week(Date.utc_today())
      outro_dia = if hoje_semana == 1, do: 2, else: 1

      {:ok, habit} =
        Priorities.set_habit_frequency(habit, %{frequency: :weekly, weekdays: [outro_dia]}, user)

      {:ok, _view, html} = live(conn, ~p"/today")

      refute html =~ "Academia"

      assert Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id)) ==
               []
    end

    test "form de captura com \"É um hábito?\" marcado cria um hábito com card no board de hoje",
         %{
           conn: conn,
           user: user
         } do
      cat = category(user, "Saúde")
      item = manual_item(user, cat, "Rotina")
      {:ok, view, _html} = live(conn, ~p"/today")

      # O campo de frequência só existe no DOM depois do phx-change revelar a
      # seção de hábito (mesmo padrão do form de tipo de item em `Index`), e a
      # prioridade só depois da categoria escolhida revelar a segunda cascata.
      view
      |> form("#capture-form", %{
        "title" => "Beber água",
        "type" => "habito",
        "category_id" => cat.id
      })
      |> render_change()

      html =
        view
        |> form("#capture-form", %{
          "title" => "Beber água",
          "type" => "habito",
          "category_id" => cat.id,
          "item_id" => item.id,
          "frequency" => "daily"
        })
        |> render_submit()

      assert html =~ "Beber água"

      assert [habit] = Priorities.list_today_activities(user) |> Enum.map(& &1.habit)
      assert habit.title == "Beber água"
      assert habit.frequency == :daily
    end

    test "seção Hábito no modal da atividade mostra sequência e persiste nova frequência", %{
      conn: conn,
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      [activity] =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      {:ok, view, _html} = live(conn, ~p"/today")
      html = render_click(view, "open_activity", %{"id" => activity.id})

      assert html =~ "0 dias seguidos"

      view
      |> element("#habit-frequency-form-#{habit.id}")
      |> render_submit(%{"frequency" => "weekly", "weekdays" => ["1", "3", "5"]})

      {:ok, atualizado} = Priorities.get_habit(habit.id, user)
      assert atualizado.frequency == :weekly
      assert atualizado.weekdays == [1, 3, 5]
    end

    test "concluir a atividade de hoje pelo card incrementa a sequência do hábito", %{
      conn: conn,
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      [activity] =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      {:ok, view, _html} = live(conn, ~p"/today")
      render_click(view, "complete_activity", %{"id" => activity.id})

      assert Priorities.habit_streak(habit.id) == 1
    end
  end

  describe "próximos dias" do
    test "lista hábito diário nos próximos dias e link de navegação funciona", %{
      conn: conn,
      user: user
    } do
      {:ok, _habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      {:ok, view, _html} = live(conn, ~p"/today")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("a", "Próximos dias") |> render_click()

      {:ok, _view2, html} = live(conn, to)
      assert html =~ "Meditar"
    end

    test "hábito semanal só aparece no dia da semana configurado", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      tomorrow_weekday = Date.day_of_week(Date.add(Date.utc_today(), 1))

      {:ok, _} =
        Priorities.set_habit_frequency(
          habit,
          %{frequency: :weekly, weekdays: [tomorrow_weekday]},
          user
        )

      {:ok, _view, html} = live(conn, ~p"/today/upcoming")

      tomorrow = Date.add(Date.utc_today(), 1)
      document = LazyHTML.from_fragment(html)
      first_day = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(tomorrow)}")
      assert LazyHTML.to_html(first_day) =~ "Academia"
    end

    test "hábito arquivado não aparece", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Pausado", item_id: habit_item(user).id})

      {:ok, _} = Priorities.archive_habit(habit, user)

      {:ok, _view, html} = live(conn, ~p"/today/upcoming")

      refute html =~ "Pausado"
    end

    test "clicar num hábito abre o HabitModal com frequência e streak", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      tomorrow = Date.add(Date.utc_today(), 1)

      {:ok, view, _html} = live(conn, ~p"/today/upcoming")

      html =
        render_click(view, "open_habit", %{"id" => habit.id, "date" => Date.to_iso8601(tomorrow)})

      assert html =~ "habit-frequency-form-#{habit.id}"
      assert html =~ "0 dias seguidos"
    end

    test "excluir pelo HabitModal remove o hábito da prévia", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      tomorrow = Date.add(Date.utc_today(), 1)

      {:ok, view, _html} = live(conn, ~p"/today/upcoming")
      render_click(view, "open_habit", %{"id" => habit.id, "date" => Date.to_iso8601(tomorrow)})

      view
      |> element("#habit-modal-#{habit.id}-#{Date.to_iso8601(tomorrow)} button", "Excluir")
      |> render_click()

      assert {:error, _} = Priorities.get_habit(habit.id, user)
    end

    test "pular um dia específico tira o hábito só daquele dia", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      tomorrow = Date.add(Date.utc_today(), 1)
      depois = Date.add(tomorrow, 1)

      {:ok, view, _html} = live(conn, ~p"/today/upcoming")
      render_click(view, "open_habit", %{"id" => habit.id, "date" => Date.to_iso8601(tomorrow)})

      view
      |> element("#habit-occurrence-form-#{habit.id}-#{Date.to_iso8601(tomorrow)}")
      |> render_submit(%{"skipped" => "true"})

      html = render_click(view, "close_habit_modal", %{})
      document = LazyHTML.from_fragment(html)

      dia_pulado = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(tomorrow)}")
      refute LazyHTML.to_html(dia_pulado) =~ "Meditar"

      dia_seguinte = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(depois)}")
      assert LazyHTML.to_html(dia_seguinte) =~ "Meditar"
    end

    test "renomear um dia mostra o título de exceção só naquele card", %{conn: conn, user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      tomorrow = Date.add(Date.utc_today(), 1)
      depois = Date.add(tomorrow, 1)

      {:ok, view, _html} = live(conn, ~p"/today/upcoming")
      render_click(view, "open_habit", %{"id" => habit.id, "date" => Date.to_iso8601(tomorrow)})

      view
      |> element("#habit-occurrence-form-#{habit.id}-#{Date.to_iso8601(tomorrow)}")
      |> render_submit(%{"title" => "Academia - perna"})

      html = render_click(view, "close_habit_modal", %{})
      document = LazyHTML.from_fragment(html)

      dia = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(tomorrow)}")
      assert LazyHTML.to_html(dia) =~ "Academia - perna"

      dia_seguinte = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(depois)}")
      html_seguinte = LazyHTML.to_html(dia_seguinte)
      assert html_seguinte =~ "Academia"
      refute html_seguinte =~ "Academia - perna"
    end

    test "\"essa e as próximas\" cria um hábito novo e preserva a regra antiga antes da data", %{
      conn: conn,
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      data_corte = Date.add(Date.utc_today(), 3)

      {:ok, view, _html} = live(conn, ~p"/today/upcoming")

      render_click(view, "open_habit", %{
        "id" => habit.id,
        "date" => Date.to_iso8601(data_corte)
      })

      view
      |> element("#habit-frequency-form-#{habit.id}")
      |> render_submit(%{
        "frequency" => "weekly",
        "weekdays" => ["1", "3", "5"],
        "scope" => "from_here"
      })

      {:ok, antigo} = Priorities.get_habit(habit.id, user)
      assert antigo.ends_on == Date.add(data_corte, -1)
      assert antigo.frequency == :daily

      novos =
        Priorities.upcoming_habit_schedule(user, 7)
        |> Enum.flat_map(& &1.habits)
        |> Enum.map(& &1.habit)
        |> Enum.filter(&(&1.id != habit.id))
        |> Enum.uniq_by(& &1.id)

      assert [novo] = novos
      assert novo.starts_on == data_corte
      assert novo.frequency == :weekly
    end

    test "atividade adiada aparece no dia em que volta, e cancelar o adiamento a devolve pra tela do dia",
         %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Trabalho")
      act = activity(user, item, "Relatório")
      segunda = Date.add(Date.utc_today(), 3)
      {:ok, act} = Priorities.snooze_activity(act, segunda, user)

      {:ok, view, html} = live(conn, ~p"/today/upcoming")

      document = LazyHTML.from_fragment(html)
      dia = LazyHTML.query(document, "#upcoming-day-#{Date.to_iso8601(segunda)}")
      assert LazyHTML.to_html(dia) =~ "Relatório"

      render_click(view, "cancel_snooze", %{"id" => act.id})

      {:ok, updated} = Priorities.get_activity(act.id, user)
      assert is_nil(updated.snoozed_until)
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
