defmodule QuizProjectWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use QuizProjectWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint QuizProjectWeb.Endpoint

      use QuizProjectWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import QuizProjectWeb.ConnCase
    end
  end

  setup tags do
    QuizProject.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Cria um usuário e o loga na sessão da conn, com token de participante.
  """
  def register_and_log_in_user(%{conn: conn}) do
    {:ok, user} =
      QuizProject.Accounts.register_user(
        %{email: "user#{System.unique_integer([:positive])}@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{conn: log_in_user(conn, user), user: user}
  end

  def log_in_user(conn, user, participant_token \\ "token-teste") do
    conn
    |> Phoenix.ConnTest.init_test_session(%{
      user_id: user.id,
      participant_token: participant_token
    })
  end

  @doc "Sessão anônima apenas com token de participante."
  def anonymous_session(conn, participant_token \\ "token-anonimo") do
    Phoenix.ConnTest.init_test_session(conn, %{participant_token: participant_token})
  end
end
