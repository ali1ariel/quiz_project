defmodule QuizProject.Priorities.GoogleCalendarSyncTest do
  # `google_req_options` é configuração global do app — ver comentário em
  # `QuizProject.GoogleCalendar.OAuthTest`. `:jobs_mode` já é `:inline` em
  # `config/test.exs`, então o sync de saída roda no próprio processo do
  # teste (sem polling) e pode até fazer `assert` de dentro do stub.
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.Priorities

  setup do
    Application.put_env(:quiz_project, :google_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:quiz_project, :google_req_options) end)

    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user}
  end

  defp connect_google(user) do
    {:ok, connection} =
      Accounts.upsert_google_calendar_connection(user, %{
        google_account_email: "dono@gmail.com",
        access_token: "access-1",
        refresh_token: "refresh-1",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        calendar_id: "calendar-1"
      })

    connection
  end

  defp stub_event_response(status \\ 200, id \\ "evt-1") do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"id" => id, "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)
  end

  defp decode_body!(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  test "sem conexão do Google, criar atividade não chama a API", %{user: user} do
    Req.Test.stub(__MODULE__, fn _conn -> flunk("não deveria chamar o Google sem conexão") end)

    assert {:ok, activity} = Priorities.create_activity(user, %{title: "Sem Google"})
    assert is_nil(activity.google_event_id)
  end

  test "criar atividade com Google conectado insere o evento e vincula o id", %{user: user} do
    connect_google(user)
    stub_event_response()

    assert {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

    assert {:ok, fetched} = Priorities.get_activity(activity.id, user)
    assert fetched.google_event_id == "evt-1"
    assert fetched.google_updated_at != nil
  end

  test "o evento criado usa end.date exclusivo (logical_date + 1) e não leva colorId quando pendente",
       %{user: user} do
    connect_google(user)
    hoje = QuizProject.Priorities.Clock.today()

    Req.Test.stub(__MODULE__, fn conn ->
      {body, conn} = decode_body!(conn)

      assert body["summary"] == "Ler capítulo 1"
      assert body["start"]["date"] == Date.to_iso8601(hoje)
      assert body["end"]["date"] == Date.to_iso8601(Date.add(hoje, 1))
      refute Map.has_key?(body, "colorId")

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})
  end

  test "concluir a atividade faz PATCH no evento existente com colorId verde (10)", %{
    user: user
  } do
    connect_google(user)
    stub_event_response()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path =~ "evt-1"
      {body, conn} = decode_body!(conn)
      assert body["colorId"] == "10"

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _completed} = Priorities.complete_activity(activity, user)
  end

  test "marcar não cumprida usa colorId vermelho (11)", %{user: user} do
    connect_google(user)
    stub_event_response()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

    Req.Test.stub(__MODULE__, fn conn ->
      {body, conn} = decode_body!(conn)
      assert body["colorId"] == "11"

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _} = Priorities.mark_activity_not_done(activity, user)
  end

  test "descartar a atividade faz PATCH com colorId cinza (8), sem apagar o evento", %{
    user: user
  } do
    connect_google(user)
    stub_event_response()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      {body, conn} = decode_body!(conn)
      assert body["colorId"] == "8"

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _discarded} = Priorities.discard_activity(activity, user)
  end

  test "adiar a atividade usa colorId amarelo (5)", %{user: user} do
    connect_google(user)
    stub_event_response()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})

    Req.Test.stub(__MODULE__, fn conn ->
      {body, conn} = decode_body!(conn)
      assert body["colorId"] == "5"

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _snoozed} =
             Priorities.snooze_activity(activity, Date.add(Date.utc_today(), 2), user)
  end

  test "corrigir o status no Histórico não sincroniza com o Google", %{user: user} do
    connect_google(user)
    stub_event_response()
    {:ok, activity} = Priorities.create_activity(user, %{title: "Ler capítulo 1"})
    {:ok, completed} = Priorities.complete_activity(activity, user)

    Req.Test.stub(__MODULE__, fn _conn ->
      flunk("correct_activity_status não deveria chamar o Google")
    end)

    assert {:ok, _corrected} = Priorities.correct_activity_status(completed, :nao_cumprida, user)
  end

  test "atividade criada antes de conectar o Google é criada (não trava tentando um PATCH) na próxima mutação",
       %{user: user} do
    Req.Test.stub(__MODULE__, fn _conn -> flunk("não deveria chamar o Google sem conexão") end)
    {:ok, activity} = Priorities.create_activity(user, %{title: "Antes de conectar"})
    assert is_nil(activity.google_event_id)

    connect_google(user)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"

      Req.Test.json(conn, %{"id" => "evt-1", "updated" => DateTime.to_iso8601(DateTime.utc_now())})
    end)

    assert {:ok, _updated} =
             Priorities.update_activity(activity, %{title: "Depois de conectar"}, user)

    assert {:ok, fetched} = Priorities.get_activity(activity.id, user)
    assert fetched.google_event_id == "evt-1"
  end

  test "falha HTTP na chamada ao Google não impede a mutação local", %{user: user} do
    connect_google(user)

    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:ok, activity} = Priorities.create_activity(user, %{title: "Mesmo com Google fora"})
    assert is_nil(activity.google_event_id)
  end
end
