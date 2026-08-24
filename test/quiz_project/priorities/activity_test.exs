defmodule QuizProject.Priorities.ActivityTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Priorities

  setup do
    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "outra@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user, other: other}
  end

  defp category(user, name \\ "Categoria") do
    {:ok, category} = Priorities.create_category(user, %{name: name})
    category
  end

  defp manual_item(user, category, title \\ "Item") do
    {:ok, item} = Priorities.create_item(user, category, %{item_type: :manual, title: title})
    item
  end

  describe "criação" do
    test "cria atividade presa a um item, com logical_date default de hoje", %{user: user} do
      item = manual_item(user, category(user))

      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Ler capítulo 1", item_id: item.id})

      assert activity.item_id == item.id
      assert activity.status == :pendente
      assert activity.flow == :todo
      assert activity.logical_date == Date.utc_today()
    end

    test "list_activities_for_item lista independente da data, só do dono", %{
      user: user,
      other: other
    } do
      item = manual_item(user, category(user))

      {:ok, hoje} = Priorities.create_activity(user, %{title: "Hoje", item_id: item.id})

      {:ok, antiga} =
        Priorities.create_activity(user, %{
          title: "Antiga",
          item_id: item.id,
          logical_date: Date.add(Date.utc_today(), -10)
        })

      ids = Priorities.list_activities_for_item(item.id, user) |> Enum.map(& &1.id)
      assert hoje.id in ids
      assert antiga.id in ids
      assert Priorities.list_activities_for_item(item.id, other) == []
    end

    test "aceita logical_date explícito", %{user: user} do
      past = Date.add(Date.utc_today(), -3)

      {:ok, activity} = Priorities.create_activity(user, %{title: "Antiga", logical_date: past})

      assert activity.logical_date == past
    end

    test "sem item_id vira captura solta", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Comprar pão"})

      assert activity.item_id == nil
      assert Enum.map(Priorities.list_loose_captures(user), & &1.id) == [activity.id]
      assert Priorities.count_loose_captures(user) == 1
    end

    test "rejeita item de outro usuário", %{user: user, other: other} do
      item = manual_item(other, category(other))

      assert {:error, :unauthorized} =
               Priorities.create_activity(user, %{title: "X", item_id: item.id})
    end
  end

  describe "triagem" do
    test "assign_activity_to_item resolve uma captura solta", %{user: user} do
      item = manual_item(user, category(user), "Estudar Elixir")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Ver capítulo de GenServer"})

      {:ok, updated} = Priorities.assign_activity_to_item(activity, item, user)

      assert updated.item_id == item.id
      assert Priorities.list_loose_captures(user) == []
    end

    test "suggest_items_for_activity casa por texto, senão cai pros mais recentes", %{user: user} do
      cat = category(user)
      _antigo = manual_item(user, cat, "Item qualquer")
      alvo = manual_item(user, cat, "Estudar Elixir")

      {:ok, com_match} = Priorities.create_activity(user, %{title: "revisar Elixir hoje"})
      {:ok, sem_match} = Priorities.create_activity(user, %{title: "zzz nada a ver zzz"})

      assert alvo.id in Enum.map(Priorities.suggest_items_for_activity(com_match), & &1.id)
      assert Priorities.suggest_items_for_activity(sem_match) != []
    end
  end

  describe "transições de status/flow" do
    test "start move flow pra fazendo sem mexer no status", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      {:ok, started} = Priorities.start_activity(activity, user)

      assert started.flow == :fazendo
      assert started.status == :pendente
    end

    test "back_to_todo desfaz start", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})
      {:ok, started} = Priorities.start_activity(activity, user)

      {:ok, back} = Priorities.back_to_todo_activity(started, user)

      assert back.flow == :todo
    end

    test "back_to_todo rejeitado se não está em fazendo", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      assert {:error, %Ash.Error.Invalid{}} = Priorities.back_to_todo_activity(activity, user)
    end

    test "complete grava status e flow", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      {:ok, done} = Priorities.complete_activity(activity, user)

      assert done.status == :concluida
      assert done.flow == :feito
    end

    test "mark_not_done grava status e flow", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      {:ok, done} = Priorities.mark_activity_not_done(activity, user)

      assert done.status == :nao_cumprida
      assert done.flow == :feito
    end

    test "discard grava status e flow", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      {:ok, done} = Priorities.discard_activity(activity, user)

      assert done.status == :descartada
      assert done.flow == :feito
    end

    test "start rejeitado se a atividade já foi resolvida", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})
      {:ok, done} = Priorities.complete_activity(activity, user)

      assert {:error, %Ash.Error.Invalid{}} = Priorities.start_activity(done, user)
    end

    test "sem limite de WIP: duas atividades do mesmo usuário podem estar em fazendo ao mesmo tempo",
         %{user: user} do
      {:ok, a} = Priorities.create_activity(user, %{title: "A"})
      {:ok, b} = Priorities.create_activity(user, %{title: "B"})

      {:ok, a} = Priorities.start_activity(a, user)
      {:ok, b} = Priorities.start_activity(b, user)

      assert a.flow == :fazendo
      assert b.flow == :fazendo
    end
  end

  describe "autorização" do
    test "outro usuário não opera atividade alheia", %{user: user, other: other} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      assert {:error, :unauthorized} = Priorities.get_activity(activity.id, other)
      assert {:error, :unauthorized} = Priorities.start_activity(activity, other)
      assert {:error, :unauthorized} = Priorities.complete_activity(activity, other)
    end
  end

  describe "tela do dia" do
    test "list_today_lanes só traz atividades de hoje, agrupadas por item e flow", %{user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Estudar Elixir")

      {:ok, hoje} = Priorities.create_activity(user, %{title: "Hoje", item_id: item.id})

      {:ok, ontem} =
        Priorities.create_activity(user, %{
          title: "Ontem",
          item_id: item.id,
          logical_date: Date.add(Date.utc_today(), -1)
        })

      {:ok, hoje_fazendo} = Priorities.start_activity(hoje, user)

      [lane] = Priorities.list_today_lanes(user)

      assert lane.item.id == item.id
      ids_todo = Enum.map(Map.get(lane.activities, :todo, []), & &1.id)
      ids_fazendo = Enum.map(Map.get(lane.activities, :fazendo, []), & &1.id)

      refute ontem.id in ids_todo
      refute ontem.id in ids_fazendo
      assert hoje_fazendo.id in ids_fazendo
    end
  end

  describe "vínculos entre itens" do
    test "cria vínculo e aparece nos dois itens com direção e rótulo corretos", %{user: user} do
      cat = category(user)
      livro = manual_item(user, cat, "Livro de Elixir")
      materia = manual_item(user, cat, "Programação funcional")

      {:ok, _link} = Priorities.create_item_link(livro, materia, :contribui_para, user)

      {:ok, links_livro} = Priorities.list_item_links(livro, user)
      {:ok, links_materia} = Priorities.list_item_links(materia, user)

      assert [%{direction: :out, item: %{id: id}, label: "contribui para"}] = links_livro
      assert id == materia.id

      assert [%{direction: :in, item: %{id: id2}, label: "recebe contribuição de"}] =
               links_materia

      assert id2 == livro.id
    end

    test "rejeita auto-vínculo", %{user: user} do
      item = manual_item(user, category(user))

      assert {:error, %Ash.Error.Invalid{}} =
               Priorities.create_item_link(item, item, :relacionado_a, user)
    end

    test "dois link_type diferentes convivem no mesmo par; o mesmo tipo repetido é rejeitado", %{
      user: user
    } do
      cat = category(user)
      a = manual_item(user, cat, "A")
      b = manual_item(user, cat, "B")

      assert {:ok, _} = Priorities.create_item_link(a, b, :parte_de, user)
      assert {:ok, _} = Priorities.create_item_link(a, b, :relacionado_a, user)
      assert {:error, %Ash.Error.Invalid{}} = Priorities.create_item_link(a, b, :parte_de, user)
    end

    test "delete_item_link remove dos dois lados", %{user: user} do
      cat = category(user)
      a = manual_item(user, cat, "A")
      b = manual_item(user, cat, "B")

      {:ok, link} = Priorities.create_item_link(a, b, :parte_de, user)
      {:ok, _} = Priorities.delete_item_link(link, a, user)

      assert {:ok, []} = Priorities.list_item_links(a, user)
      assert {:ok, []} = Priorities.list_item_links(b, user)
    end
  end

  describe "descrição" do
    test "update_activity grava título e notas", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      {:ok, updated} =
        Priorities.update_activity(activity, %{title: "B", notes: "mais contexto"}, user)

      assert updated.title == "B"
      assert updated.notes == "mais contexto"
    end
  end

  describe "checklist de atividade" do
    test "cria subitens em posições crescentes", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Organizar mudança"})

      {:ok, t1} = Priorities.create_activity_task(activity, "Separar caixas", user)
      {:ok, t2} = Priorities.create_activity_task(activity, "Chamar frete", user)

      assert t1.position == 0
      assert t2.position == 1

      assert Enum.map(Priorities.list_activity_tasks(activity.id), & &1.title) == [
               "Separar caixas",
               "Chamar frete"
             ]
    end

    test "toggle_activity_task alterna done", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})
      {:ok, task} = Priorities.create_activity_task(activity, "Subitem", user)
      refute task.done

      {:ok, marcado} = Priorities.toggle_activity_task(task, activity, user)
      assert marcado.done

      {:ok, desmarcado} = Priorities.toggle_activity_task(marcado, activity, user)
      refute desmarcado.done
    end

    test "delete_activity_task remove o subitem", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})
      {:ok, task} = Priorities.create_activity_task(activity, "Subitem", user)

      {:ok, _} = Priorities.delete_activity_task(task, activity, user)

      assert Priorities.list_activity_tasks(activity.id) == []
    end

    test "outro usuário não opera checklist alheio", %{user: user, other: other} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})
      {:ok, task} = Priorities.create_activity_task(activity, "Subitem", user)

      assert {:error, :unauthorized} = Priorities.create_activity_task(activity, "X", other)
      assert {:error, :unauthorized} = Priorities.toggle_activity_task(task, activity, other)
      assert {:error, :unauthorized} = Priorities.delete_activity_task(task, activity, other)
    end
  end
end
