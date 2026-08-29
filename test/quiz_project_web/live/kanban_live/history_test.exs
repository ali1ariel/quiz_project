defmodule QuizProjectWeb.KanbanLive.HistoryTest do
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

  defp resolved_yesterday(user, item, title, status) do
    {:ok, activity} = Priorities.create_activity(user, %{title: title, item_id: item.id})

    resolve =
      if status == :concluida,
        do: &Priorities.complete_activity/2,
        else: &Priorities.mark_activity_not_done/2

    {:ok, activity} = resolve.(activity, user)

    activity
    |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:resolved_date, Date.add(Date.utc_today(), -1))
    |> Ash.update!()
  end

  describe "histórico" do
    test "título da atividade não é clicável — histórico é só consulta", %{conn: conn, user: user} do
      item = manual_item(user, category(user), "Item")
      resolved_yesterday(user, item, "Resolvida ontem", :concluida)

      {:ok, view, _html} =
        live(conn, ~p"/today/history?date=#{Date.to_iso8601(Date.add(Date.utc_today(), -1))}")

      assert has_element?(view, "span", "Resolvida ontem")
      refute has_element?(view, "button[phx-click='open_activity']", "Resolvida ontem")
    end

    test "corrigir desfecho troca o status sem mudar o dia em que a atividade aparece", %{
      conn: conn,
      user: user
    } do
      item = manual_item(user, category(user), "Item")
      activity = resolved_yesterday(user, item, "Marcada errado", :nao_cumprida)
      ontem = Date.add(Date.utc_today(), -1)

      {:ok, view, html} = live(conn, ~p"/today/history?date=#{Date.to_iso8601(ontem)}")
      assert html =~ "Marcada errado"

      view
      |> element(
        "button[phx-click='correct_status'][phx-value-id='#{activity.id}'][phx-value-status='concluida']"
      )
      |> render_click()

      updated = Ash.get!(Priorities.Activity, activity.id, authorize?: false)
      assert updated.status == :concluida
      assert updated.resolved_date == ontem

      html = render(view)
      assert html =~ "Marcada errado"
    end

    test "atividade presa a item ainda pendente não aparece no histórico (só quando resolvida)",
         %{
           conn: conn,
           user: user
         } do
      cat = category(user)
      item = manual_item(user, cat, "Item")

      {:ok, _pending} =
        Priorities.create_activity(user, %{title: "Ainda em aberto", item_id: item.id})

      {:ok, view, html} = live(conn, ~p"/today/history")

      refute html =~ "Ainda em aberto"
      refute has_element?(view, "button[phx-value-status='concluida']")
    end
  end
end
