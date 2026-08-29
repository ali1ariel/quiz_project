defmodule QuizProject.GoogleCalendar.WatchRenewerTest do
  # Ver comentário em `OAuthTest` sobre `google_req_options` ser global.
  # `WatchRenewer` não sobe de verdade na suíte (`enable_google_calendar_watch_renewer:
  # false` em config/test.exs) — aqui chamamos `handle_info/2` direto, sem
  # timer real, como o plano pede.
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.GoogleCalendar.WatchRenewer

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)

    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user}
  end

  defp connection_attrs do
    %{
      google_account_email: "dono@gmail.com",
      access_token: "access-1",
      refresh_token: "refresh-1",
      access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      calendar_id: "calendar-1"
    }
  end

  defp stub_renewal do
    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        String.ends_with?(conn.request_path, "/channels/stop") ->
          Plug.Conn.send_resp(conn, 200, "")

        String.ends_with?(conn.request_path, "/events/watch") ->
          Req.Test.json(conn, %{"resourceId" => "resource-novo", "expiration" => "9999999999999"})

        conn.method == "GET" and String.ends_with?(conn.request_path, "/events") ->
          Req.Test.json(conn, %{"items" => [], "nextSyncToken" => "sync-token-novo"})
      end
    end)
  end

  test "renova conexão que ainda não tem canal registrado", %{user: user} do
    {:ok, _connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())
    stub_renewal()

    assert {:noreply, %{}} = WatchRenewer.handle_info(:renew, %{})

    assert {:ok, renovada} = Accounts.get_google_calendar_connection(user)
    assert renovada.channel_id != nil
    assert renovada.channel_resource_id == "resource-novo"
    assert renovada.sync_token == "sync-token-novo"
  end

  test "renova conexão cujo canal expira dentro de 24h", %{user: user} do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())

    {:ok, connection} =
      Accounts.update_google_calendar_watch_channel(connection, %{
        channel_id: "canal-velho",
        channel_token_hash: "hash-velho",
        channel_resource_id: "resource-velho",
        channel_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    stub_renewal()

    WatchRenewer.handle_info(:renew, %{})

    assert {:ok, renovada} = Accounts.get_google_calendar_connection(user)
    assert renovada.channel_id != connection.channel_id
    assert renovada.channel_resource_id == "resource-novo"
  end

  test "não mexe em conexão cujo canal ainda vale por muito tempo", %{user: user} do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())

    {:ok, connection} =
      Accounts.update_google_calendar_watch_channel(connection, %{
        channel_id: "canal-valido",
        channel_token_hash: "hash-valido",
        channel_resource_id: "resource-valido",
        channel_expires_at: DateTime.add(DateTime.utc_now(), 10 * 24 * 3600, :second)
      })

    Req.Test.stub(__MODULE__, fn _conn ->
      flunk("não deveria chamar o Google pra uma conexão com canal ainda válido")
    end)

    WatchRenewer.handle_info(:renew, %{})

    assert {:ok, intacta} = Accounts.get_google_calendar_connection(user)
    assert intacta.channel_id == connection.channel_id
    assert intacta.channel_resource_id == connection.channel_resource_id
  end
end
