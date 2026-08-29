defmodule QuizProject.GoogleCalendar.ReconcileTest do
  # Ver comentário em `OAuthTest` sobre `google_req_options` ser global.
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar
  alias QuizProject.Priorities

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)

    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, connection} =
      Accounts.upsert_google_calendar_connection(user, %{
        google_account_email: "dono@gmail.com",
        access_token: "access-1",
        refresh_token: "refresh-1",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        calendar_id: "calendar-1"
      })

    %{user: user, connection: connection}
  end

  defp stub_list(items, extra \\ %{"nextSyncToken" => "sync-token-2"}) do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, Map.put(extra, "items", items))
    end)
  end

  # A conexão já existe (setup), então qualquer `Priorities.create_activity`/
  # `complete_activity` chamado ANTES do `stub_list` do teste (pra montar o
  # cenário) já dispara sync de saída — precisa de algum stub no ar, senão
  # o `Req.Test` não acha nenhum stub configurado ainda.
  defp stub_outbound_ok do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "id" => "evt-saida-ignorado",
        "updated" => DateTime.to_iso8601(DateTime.utc_now())
      })
    end)
  end

  test "evento novo de dia inteiro sem atividade correspondente vira captura solta", %{
    user: user,
    connection: connection
  } do
    stub_list([
      %{
        "id" => "evt-novo",
        "status" => "confirmed",
        "summary" => "Reunião marcada direto no Google",
        "description" => "notas do evento",
        "start" => %{"date" => "2026-09-01"},
        "updated" => "2026-08-29T10:00:00.000Z"
      }
    ])

    GoogleCalendar.reconcile(connection)

    assert {:ok, activity} = Priorities.get_activity_by_google_event_id("evt-novo")
    assert activity.title == "Reunião marcada direto no Google"
    assert activity.notes == "notas do evento"
    assert activity.logical_date == ~D[2026-09-01]
    assert is_nil(activity.item_id)
    assert is_nil(activity.habit_id)
    assert activity.user_id == user.id

    assert {:ok, updated_connection} = Accounts.get_google_calendar_connection(user)
    assert updated_connection.sync_token == "sync-token-2"
  end

  test "evento novo com horário (dateTime) é ignorado, sem criar atividade", %{
    connection: connection
  } do
    stub_list([
      %{
        "id" => "evt-com-horario",
        "status" => "confirmed",
        "summary" => "Reunião com hora marcada",
        "start" => %{"dateTime" => "2026-09-01T10:00:00-03:00"},
        "updated" => "2026-08-29T10:00:00.000Z"
      }
    ])

    GoogleCalendar.reconcile(connection)

    assert {:error, :not_found} = Priorities.get_activity_by_google_event_id("evt-com-horario")
  end

  test "evento cancelado desfaz o vínculo sem mexer em status/flow", %{
    user: user,
    connection: connection
  } do
    stub_outbound_ok()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})
    {:ok, completed} = Priorities.complete_activity(activity, user)

    {:ok, linked} =
      Priorities.link_google_event(completed, "evt-cancelado", DateTime.utc_now())

    stub_list([%{"id" => "evt-cancelado", "status" => "cancelled"}])

    GoogleCalendar.reconcile(connection)

    assert {:ok, fetched} = Priorities.get_activity(linked.id, user)
    assert is_nil(fetched.google_event_id)
    assert is_nil(fetched.google_updated_at)
    assert fetched.status == :concluida
    assert fetched.flow == :feito
  end

  test "cancelar um evento sem atividade correspondente não quebra", %{connection: connection} do
    stub_list([%{"id" => "evt-orfao", "status" => "cancelled"}])
    GoogleCalendar.reconcile(connection)
  end

  test "edição real no Google (updated mais novo) aplica título/notas/data", %{
    user: user,
    connection: connection
  } do
    stub_outbound_ok()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Original"})
    antigo = DateTime.add(DateTime.utc_now(), -3600, :second)
    {:ok, linked} = Priorities.link_google_event(activity, "evt-1", antigo)

    nova_data = Date.add(linked.logical_date, 3)

    stub_list([
      %{
        "id" => "evt-1",
        "status" => "confirmed",
        "summary" => "Editado no Google",
        "description" => "notas editadas",
        "start" => %{"date" => Date.to_iso8601(nova_data)},
        "updated" => DateTime.to_iso8601(DateTime.utc_now())
      }
    ])

    GoogleCalendar.reconcile(connection)

    assert {:ok, fetched} = Priorities.get_activity(linked.id, user)
    assert fetched.title == "Editado no Google"
    assert fetched.notes == "notas editadas"
    assert fetched.logical_date == nova_data
  end

  test "não sobrescreve logical_date de atividade já resolvida", %{
    user: user,
    connection: connection
  } do
    stub_outbound_ok()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Original"})
    {:ok, resolved} = Priorities.complete_activity(activity, user)
    data_original = resolved.logical_date
    antigo = DateTime.add(DateTime.utc_now(), -3600, :second)
    {:ok, linked} = Priorities.link_google_event(resolved, "evt-1", antigo)

    stub_list([
      %{
        "id" => "evt-1",
        "status" => "confirmed",
        "summary" => "Editado no Google",
        "start" => %{"date" => Date.to_iso8601(Date.add(data_original, 10))},
        "updated" => DateTime.to_iso8601(DateTime.utc_now())
      }
    ])

    GoogleCalendar.reconcile(connection)

    assert {:ok, fetched} = Priorities.get_activity(linked.id, user)
    assert fetched.title == "Editado no Google"
    assert fetched.logical_date == data_original
  end

  test "evento com updated não mais novo que o conhecido é ignorado (eco da própria escrita)", %{
    user: user,
    connection: connection
  } do
    stub_outbound_ok()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Original"})
    agora = DateTime.utc_now()
    {:ok, linked} = Priorities.link_google_event(activity, "evt-1", agora)

    stub_list([
      %{
        "id" => "evt-1",
        "status" => "confirmed",
        "summary" => "Não deveria aplicar",
        "start" => %{"date" => Date.to_iso8601(linked.logical_date)},
        "updated" => DateTime.to_iso8601(agora)
      }
    ])

    GoogleCalendar.reconcile(connection)

    assert {:ok, fetched} = Priorities.get_activity(linked.id, user)
    assert fetched.title == "Original"
  end

  test "410 Gone limpa o sync_token e refaz uma listagem completa", %{connection: connection} do
    connection =
      case Accounts.update_google_calendar_sync_state(connection, "sync-token-velho") do
        {:ok, updated} -> updated
      end

    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      query = URI.decode_query(conn.query_string)

      cond do
        Map.has_key?(query, "syncToken") ->
          send(test_pid, :chamada_com_sync_token_velho)
          conn |> Plug.Conn.put_status(410) |> Req.Test.json(%{"error" => "sync token velho"})

        true ->
          send(test_pid, :chamada_sem_sync_token)
          Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-recomecado"})
      end
    end)

    GoogleCalendar.reconcile(connection)

    assert_received :chamada_com_sync_token_velho
    assert_received :chamada_sem_sync_token

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(%{id: connection.user_id})
    assert fetched.sync_token == "sync-token-recomecado"
  end

  test "segue a paginação (nextPageToken) antes de gravar o sync_token final", %{
    connection: connection
  } do
    Req.Test.stub(__MODULE__, fn conn ->
      query = URI.decode_query(conn.query_string)

      if query["pageToken"] == "pagina-2" do
        Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-final"})
      else
        Req.Test.json(conn, %{"items" => [], "nextPageToken" => "pagina-2"})
      end
    end)

    GoogleCalendar.reconcile(connection)

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(%{id: connection.user_id})
    assert fetched.sync_token == "sync-token-final"
  end
end
