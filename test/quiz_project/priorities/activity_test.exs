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
      assert activity.kind == :tarefa
    end

    test "cria atividade do tipo evento, com data escolhida", %{user: user} do
      data = Date.add(Date.utc_today(), 5)

      {:ok, activity} =
        Priorities.create_activity(user, %{title: "Reunião", kind: :evento, logical_date: data})

      assert activity.kind == :evento
      assert activity.logical_date == data
    end

    test "kind rejeita valor fora de tarefa/evento", %{user: user} do
      assert {:error, %Ash.Error.Invalid{}} =
               Priorities.create_activity(user, %{title: "X", kind: :outro})
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

    test "reopen desfaz complete/mark_not_done/discard, voltando pra pendente/a fazer", %{
      user: user
    } do
      {:ok, concluida} = Priorities.create_activity(user, %{title: "A"})
      {:ok, concluida} = Priorities.complete_activity(concluida, user)
      {:ok, reaberta} = Priorities.reopen_activity(concluida, user)

      assert reaberta.status == :pendente
      assert reaberta.flow == :todo
    end

    test "reopen rejeitado se a atividade ainda não foi resolvida", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "A"})

      assert {:error, %Ash.Error.Invalid{}} = Priorities.reopen_activity(activity, user)
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
    test "list_today_activities_by_flow agrupa por flow, sem expirar atividade presa a item", %{
      user: user
    } do
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

      by_flow = Priorities.list_today_activities_by_flow(user)
      ids_todo = Map.get(by_flow, :todo, []) |> Enum.map(& &1.id)
      ids_fazendo = Map.get(by_flow, :fazendo, []) |> Enum.map(& &1.id)

      assert ontem.id in ids_todo
      refute ontem.id in ids_fazendo
      assert hoje_fazendo.id in ids_fazendo
    end

    test "list_today_activities carrega a categoria do item/hábito associado", %{user: user} do
      cat = category(user, "Corpo")
      item = manual_item(user, cat, "Academia")
      {:ok, _} = Priorities.create_activity(user, %{title: "Hoje", item_id: item.id})

      [activity] = Priorities.list_today_activities(user)

      assert activity.item.category.name == "Corpo"
    end

    test "evento só aparece na tela do dia no seu próprio dia, mesmo preso a item", %{user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Projeto")

      {:ok, hoje} =
        Priorities.create_activity(user, %{title: "Reunião hoje", item_id: item.id, kind: :evento})

      {:ok, _futuro} =
        Priorities.create_activity(user, %{
          title: "Reunião futura",
          item_id: item.id,
          kind: :evento,
          logical_date: Date.add(Date.utc_today(), 3)
        })

      {:ok, _passado} =
        Priorities.create_activity(user, %{
          title: "Reunião passada",
          item_id: item.id,
          kind: :evento,
          logical_date: Date.add(Date.utc_today(), -3)
        })

      ids = Priorities.list_today_activities(user) |> Enum.map(& &1.id)

      assert hoje.id in ids
      assert length(ids) == 1
    end

    test "evento resolvido hoje aparece na tela do dia mesmo que o dia marcado seja outro",
         %{user: user} do
      {:ok, evento} =
        Priorities.create_activity(user, %{
          title: "Adiantei",
          kind: :evento,
          logical_date: Date.add(Date.utc_today(), 2)
        })

      {:ok, resolvido} = Priorities.complete_activity(evento, user)

      ids = Priorities.list_today_activities(user) |> Enum.map(& &1.id)
      assert resolvido.id in ids
    end
  end

  describe "adiar" do
    test "atividade adiada some da tela do dia enquanto a data não chega", %{user: user} do
      item = manual_item(user, category(user), "Trabalho")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Relatório", item_id: item.id})

      segunda = Date.add(Date.utc_today(), 3)
      {:ok, _} = Priorities.snooze_activity(activity, segunda, user)

      refute Priorities.list_today_activities(user) |> Enum.any?(&(&1.id == activity.id))
    end

    test "quando o dia do adiamento chega, a atividade já aparece de novo (mesmo antes de limpar)",
         %{user: user} do
      item = manual_item(user, category(user), "Trabalho")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Relatório", item_id: item.id})

      # Simula a data de adiamento já ter passado — a action `:snooze` não
      # deixaria escolher isso, mas é o estado ao vivo depois de alguns dias.
      activity
      |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attribute(:snoozed_until, Date.add(Date.utc_today(), -1))
      |> Ash.update!()

      assert Priorities.list_today_activities(user) |> Enum.any?(&(&1.id == activity.id))
    end

    test "clear_expired_snoozes zera snoozed_until de adiamento já vencido", %{user: user} do
      item = manual_item(user, category(user), "Trabalho")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Relatório", item_id: item.id})

      activity
      |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attribute(:snoozed_until, Date.add(Date.utc_today(), -1))
      |> Ash.update!()

      Priorities.clear_expired_snoozes(user)

      updated = Ash.get!(Priorities.Activity, activity.id, authorize?: false)
      assert is_nil(updated.snoozed_until)
    end

    test "cancelar o adiamento antes da hora traz a atividade de volta", %{user: user} do
      item = manual_item(user, category(user), "Trabalho")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Relatório", item_id: item.id})
      {:ok, activity} = Priorities.snooze_activity(activity, Date.add(Date.utc_today(), 5), user)

      {:ok, _} = Priorities.clear_activity_snooze(activity, user)

      assert Priorities.list_today_activities(user) |> Enum.any?(&(&1.id == activity.id))
    end

    test "não deixa adiar pra hoje ou pra uma data passada", %{user: user} do
      item = manual_item(user, category(user), "Trabalho")
      {:ok, activity} = Priorities.create_activity(user, %{title: "Relatório", item_id: item.id})

      assert {:error, _} = Priorities.snooze_activity(activity, Date.utc_today(), user)

      assert {:error, _} =
               Priorities.snooze_activity(activity, Date.add(Date.utc_today(), -1), user)
    end

    test "hábito não pode ser adiado", %{user: user} do
      item = manual_item(user, category(user), "Prioridade")
      {:ok, habit} = Priorities.create_habit(user, %{title: "Hábito", item_id: item.id})
      :ok = Priorities.ensure_today_habit_instance(habit, user)

      [instancia] =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      assert {:error, _} =
               Priorities.snooze_activity(instancia, Date.add(Date.utc_today(), 1), user)
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

  describe "sincronização com Google Calendar" do
    test "list_pending_activities_from só traz eventos pendentes, nunca tarefas comuns", %{
      user: user
    } do
      hoje = Date.utc_today()

      {:ok, evento_futuro} =
        Priorities.create_activity(user, %{
          title: "Evento",
          kind: :evento,
          logical_date: Date.add(hoje, 3)
        })

      {:ok, tarefa} = Priorities.create_activity(user, %{title: "Tarefa", kind: :tarefa})

      {:ok, evento_passado} =
        Priorities.create_activity(user, %{
          title: "Evento antigo",
          kind: :evento,
          logical_date: Date.add(hoje, -3)
        })

      {:ok, evento_resolvido} =
        Priorities.create_activity(user, %{title: "Evento feito", kind: :evento})

      {:ok, evento_resolvido} = Priorities.complete_activity(evento_resolvido, user)

      resultado = Priorities.list_pending_activities_from(user, hoje)
      ids = Enum.map(resultado, & &1.id)

      assert evento_futuro.id in ids
      refute tarefa.id in ids
      refute evento_passado.id in ids
      refute evento_resolvido.id in ids
    end

    test "link_google_event grava o id do evento e o updated_at", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})
      agora = DateTime.utc_now()

      linked =
        activity
        |> Ash.Changeset.for_update(
          :link_google_event,
          %{google_event_id: "evt-1", google_updated_at: agora},
          authorize?: false
        )
        |> Ash.update!()

      assert linked.google_event_id == "evt-1"
      assert DateTime.compare(linked.google_updated_at, agora) == :eq
    end

    test "unlink_google_event limpa o vínculo sem mexer em status/flow", %{user: user} do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

      linked =
        activity
        |> Ash.Changeset.for_update(
          :link_google_event,
          %{google_event_id: "evt-1", google_updated_at: DateTime.utc_now()},
          authorize?: false
        )
        |> Ash.update!()

      {:ok, completed} = Priorities.complete_activity(linked, user)

      unlinked =
        completed
        |> Ash.Changeset.for_update(:unlink_google_event, %{}, authorize?: false)
        |> Ash.update!()

      assert is_nil(unlinked.google_event_id)
      assert is_nil(unlinked.google_updated_at)
      assert unlinked.status == :concluida
      assert unlinked.flow == :feito
    end

    test "sync_from_google aplica title/notes/logical_date numa atividade ainda não resolvida", %{
      user: user
    } do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Original"})
      nova_data = Date.add(activity.logical_date, 2)
      agora = DateTime.utc_now()

      synced =
        activity
        |> Ash.Changeset.for_update(
          :sync_from_google,
          %{
            title: "Editado no Google",
            notes: "notas novas",
            logical_date: nova_data,
            google_updated_at: agora
          },
          authorize?: false
        )
        |> Ash.update!()

      assert synced.title == "Editado no Google"
      assert synced.notes == "notas novas"
      assert synced.logical_date == nova_data
      assert DateTime.compare(synced.google_updated_at, agora) == :eq
    end

    test "sync_from_google não sobrescreve logical_date de atividade já resolvida", %{
      user: user
    } do
      {:ok, activity} = Priorities.create_activity(user, %{title: "Original"})
      {:ok, resolved} = Priorities.complete_activity(activity, user)
      data_original = resolved.logical_date
      data_arrastada_no_google = Date.add(data_original, 5)

      synced =
        resolved
        |> Ash.Changeset.for_update(
          :sync_from_google,
          %{
            title: "Editado no Google",
            logical_date: data_arrastada_no_google,
            google_updated_at: DateTime.utc_now()
          },
          authorize?: false
        )
        |> Ash.update!()

      assert synced.title == "Editado no Google"
      assert synced.logical_date == data_original
    end
  end
end
