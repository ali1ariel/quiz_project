defmodule QuizProjectWeb.AuthControllerTest do
  use QuizProjectWeb.ConnCase, async: true

  alias QuizProject.Accounts

  test "registra, loga e desloga", %{conn: conn} do
    # registro cria a conta e redireciona para o painel
    conn =
      post(conn, ~p"/criar-conta", %{
        "user" => %{"email" => "novo@teste.com", "password" => "senha12345"}
      })

    assert redirected_to(conn) == ~p"/painel"
    assert get_session(conn, :user_id)
    assert get_session(conn, :participant_token)

    # logout limpa a sessão
    conn = delete(recycle(conn), ~p"/sair")
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_id)
  end

  test "login com credenciais válidas", %{conn: conn} do
    {:ok, _} =
      Accounts.register_user(%{email: "login@teste.com", password: "senha12345"},
        authorize?: false
      )

    conn =
      post(conn, ~p"/entrar", %{
        "user" => %{"email" => "login@teste.com", "password" => "senha12345"}
      })

    assert redirected_to(conn) == ~p"/painel"
    assert get_session(conn, :user_id)
  end

  test "login com senha inválida re-renderiza com erro", %{conn: conn} do
    {:ok, _} =
      Accounts.register_user(%{email: "login@teste.com", password: "senha12345"},
        authorize?: false
      )

    conn =
      post(conn, ~p"/entrar", %{
        "user" => %{"email" => "login@teste.com", "password" => "errada123"}
      })

    assert html_response(conn, 200) =~ "login-error"
    refute get_session(conn, :user_id)
  end

  test "rota autenticada exige login", %{conn: conn} do
    conn = get(conn, ~p"/painel")
    assert redirected_to(conn) == ~p"/entrar"
  end

  test "toda visita ganha participant_token", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert get_session(conn, :participant_token)
  end
end
