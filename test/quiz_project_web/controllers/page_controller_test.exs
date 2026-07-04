defmodule QuizProjectWeb.PageControllerTest do
  use QuizProjectWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Crie e responda quizzes"
  end

  test "GET /api/docs", %{conn: conn} do
    conn = get(conn, ~p"/api/docs")
    assert html_response(conn, 200) =~ "API de quizzes"
  end
end
