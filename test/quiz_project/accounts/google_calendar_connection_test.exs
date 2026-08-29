defmodule QuizProject.Accounts.GoogleCalendarConnectionTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts

  setup do
    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user}
  end

  defp connection_attrs do
    %{
      google_account_email: "dono@gmail.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      calendar_id: "calendar-123"
    }
  end

  test "sem conexão, get retorna :not_found", %{user: user} do
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end

  test "upsert cria a conexão e get devolve os tokens em claro", %{user: user} do
    assert {:ok, connection} =
             Accounts.upsert_google_calendar_connection(user, connection_attrs())

    assert connection.access_token == "access-token"
    assert connection.refresh_token == "refresh-token"

    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == connection.id
    assert fetched.access_token == "access-token"
  end

  test "upsert de novo substitui a conexão anterior (reconexão)", %{user: user} do
    {:ok, first} = Accounts.upsert_google_calendar_connection(user, connection_attrs())

    {:ok, second} =
      Accounts.upsert_google_calendar_connection(
        user,
        %{connection_attrs() | access_token: "novo-access-token"}
      )

    assert second.id != first.id
    assert {:ok, fetched} = Accounts.get_google_calendar_connection(user)
    assert fetched.id == second.id
    assert fetched.access_token == "novo-access-token"
  end

  test "update_tokens troca o access token e mantém o refresh token quando omitido", %{
    user: user
  } do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())
    nova_expiracao = DateTime.add(DateTime.utc_now(), 7200, :second)

    assert {:ok, updated} =
             Accounts.update_google_calendar_tokens(connection, %{
               access_token: "access-renovado",
               access_token_expires_at: nova_expiracao
             })

    assert updated.access_token == "access-renovado"
    assert updated.refresh_token == "refresh-token"
  end

  test "update_tokens sobrescreve o refresh token quando o Google manda um novo", %{user: user} do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())

    assert {:ok, updated} =
             Accounts.update_google_calendar_tokens(connection, %{
               access_token: "access-renovado",
               refresh_token: "refresh-renovado",
               access_token_expires_at: DateTime.utc_now()
             })

    assert updated.refresh_token == "refresh-renovado"
  end

  test "update_watch_channel grava o estado do canal de push notifications", %{user: user} do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())
    expiracao = DateTime.add(DateTime.utc_now(), 7 * 24 * 3600, :second)

    assert {:ok, updated} =
             Accounts.update_google_calendar_watch_channel(connection, %{
               channel_id: "canal-1",
               channel_token_hash: "hash-do-token",
               channel_resource_id: "recurso-1",
               channel_expires_at: expiracao
             })

    assert updated.channel_id == "canal-1"

    assert {:ok, found} = Accounts.get_google_calendar_connection_by_channel_id("canal-1")
    assert found.id == connection.id
  end

  test "update_sync_state grava o sync_token e limpa erro anterior", %{user: user} do
    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())
    {:ok, connection} = Accounts.record_google_calendar_sync_error(connection, "boom")

    assert {:ok, updated} = Accounts.update_google_calendar_sync_state(connection, "cursor-abc")

    assert updated.sync_token == "cursor-abc"
    assert updated.last_sync_error == nil
    assert updated.last_synced_at != nil
  end

  test "disconnect exige que o dono seja o ator", %{user: user} do
    {:ok, other} =
      Accounts.register_user(%{email: "outro@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, connection} = Accounts.upsert_google_calendar_connection(user, connection_attrs())

    assert {:error, :unauthorized} = Accounts.disconnect_google_calendar(connection, other)
    assert {:ok, _} = Accounts.disconnect_google_calendar(connection, user)
    assert {:error, :not_found} = Accounts.get_google_calendar_connection(user)
  end
end
