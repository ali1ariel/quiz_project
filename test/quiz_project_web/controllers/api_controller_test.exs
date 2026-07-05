defmodule QuizProjectWeb.ApiControllerTest do
  use QuizProjectWeb.ConnCase, async: true

  alias QuizProject.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{email: "api-owner@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "api-other@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, token, _record} = Accounts.issue_api_token(user, %{name: "Testes"})
    {:ok, other_token, _record} = Accounts.issue_api_token(other, %{name: "Outro"})

    %{
      conn: api_conn(conn, token),
      anonymous_conn: api_json_conn(build_conn()),
      other_conn: api_conn(build_conn(), other_token),
      user: user,
      token: token
    }
  end

  test "expõe o schema OpenAPI publicamente", %{anonymous_conn: conn} do
    spec = conn |> get(~p"/api/openapi.json") |> json_response(200)

    assert spec["openapi"] == "3.1.0"
    assert [%{"url" => server_url}] = spec["servers"]
    assert String.ends_with?(server_url, "/api/v1")
    assert get_in(spec, ["components", "securitySchemes", "bearerAuth", "scheme"]) == "bearer"

    operation_ids =
      for {_path, operations} <- spec["paths"], {_verb, operation} <- operations do
        operation["operationId"]
      end

    assert length(operation_ids) == 13
    assert "importQuiz" in operation_ids
    assert "publishQuizVersion" in operation_ids

    # Emissão e revogação de token ficam fora do schema de propósito.
    refute Enum.any?(Map.keys(spec["paths"]), &String.contains?(&1, "auth"))
  end

  test "exige Bearer token nos endpoints protegidos", %{anonymous_conn: conn} do
    conn = get(conn, ~p"/api/v1/quizzes")
    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    assert ["Bearer realm=\"quiz-api\""] = get_resp_header(conn, "www-authenticate")
  end

  test "emite e revoga token com e-mail e senha", %{anonymous_conn: conn} do
    conn =
      post(conn, ~p"/api/v1/auth/tokens", %{
        "email" => "api-owner@teste.com",
        "password" => "senha12345",
        "name" => "CLI"
      })

    assert %{"data" => %{"token" => token, "token_type" => "Bearer"}} =
             json_response(conn, 201)

    authenticated = api_conn(build_conn(), token)
    assert %{"data" => []} = authenticated |> get(~p"/api/v1/quizzes") |> json_response(200)

    assert authenticated |> delete(~p"/api/v1/auth/token") |> response(204)

    assert authenticated |> recycle() |> get(~p"/api/v1/quizzes") |> response(401)
  end

  test "cria, lista e lê somente quizzes do usuário autenticado", %{
    conn: conn,
    other_conn: other_conn
  } do
    created =
      conn
      |> post(~p"/api/v1/quizzes", %{
        "name" => "Quiz pela API",
        "description" => "Rascunho externo",
        "total_points" => 50,
        "question_order_mode" => "random"
      })
      |> json_response(201)

    assert %{
             "data" => %{
               "name" => "Quiz pela API",
               "total_points" => "50",
               "question_order_mode" => "random",
               "status" => "draft"
             }
           } = created

    quiz_id = created["data"]["quiz_id"]

    assert %{"data" => [%{"id" => ^quiz_id}]} =
             conn |> recycle() |> get(~p"/api/v1/quizzes") |> json_response(200)

    assert %{"data" => %{"id" => ^quiz_id}} =
             conn |> recycle() |> get(~p"/api/v1/quizzes/#{quiz_id}") |> json_response(200)

    assert %{"error" => %{"code" => "not_found"}} =
             other_conn |> get(~p"/api/v1/quizzes/#{quiz_id}") |> json_response(404)
  end

  test "edita rascunho, adiciona questão, valida e publica", %{conn: conn} do
    created = conn |> post(~p"/api/v1/quizzes", %{}) |> json_response(201)
    version_id = created["data"]["id"]

    updated =
      conn
      |> recycle()
      |> patch(~p"/api/v1/quiz-versions/#{version_id}", %{"name" => "Quiz publicável"})
      |> json_response(200)

    assert updated["data"]["name"] == "Quiz publicável"

    question =
      conn
      |> recycle()
      |> post(~p"/api/v1/quiz-versions/#{version_id}/questions", %{
        "statement" => "Elixir é executado na BEAM?",
        "type" => "true_false",
        "true_false_answer" => true
      })
      |> json_response(201)

    assert question["data"]["true_false_answer"]

    assert %{"data" => %{"valid" => true, "errors" => []}} =
             conn
             |> recycle()
             |> post(~p"/api/v1/quiz-versions/#{version_id}/validate")
             |> json_response(200)

    assert %{"data" => %{"status" => "published"}} =
             conn
             |> recycle()
             |> post(~p"/api/v1/quiz-versions/#{version_id}/publish")
             |> json_response(200)

    assert %{"error" => %{"code" => "validation_error"}} =
             conn
             |> recycle()
             |> patch(~p"/api/v1/quiz-versions/#{version_id}", %{"name" => "Não pode"})
             |> json_response(422)
  end

  test "não permite alterar questão pertencente a outro usuário", %{
    conn: conn,
    other_conn: other_conn
  } do
    created = conn |> post(~p"/api/v1/quizzes", %{}) |> json_response(201)
    version_id = created["data"]["id"]

    question =
      conn
      |> recycle()
      |> post(~p"/api/v1/quiz-versions/#{version_id}/questions", %{
        "statement" => "Questão protegida",
        "type" => "text"
      })
      |> json_response(201)

    question_id = question["data"]["id"]

    assert %{"error" => %{"code" => "not_found"}} =
             other_conn
             |> patch(~p"/api/v1/questions/#{question_id}", %{"statement" => "Invadida"})
             |> json_response(404)

    assert %{"data" => %{"questions" => [%{"statement" => "Questão protegida"}]}} =
             conn
             |> recycle()
             |> get(~p"/api/v1/quiz-versions/#{version_id}")
             |> json_response(200)
  end

  test "importa o formato JSON existente", %{conn: conn} do
    response =
      conn
      |> post(~p"/api/v1/quizzes/import", %{
        "nome" => "Quiz importado",
        "questoes" => [
          %{
            "enunciado" => "A API funciona?",
            "tipo" => "verdadeiro_falso",
            "resposta_verdadeiro_falso" => true
          }
        ]
      })
      |> json_response(201)

    assert response["data"]["name"] == "Quiz importado"
    assert length(response["data"]["questions"]) == 1
  end

  defp api_conn(conn, token) do
    conn
    |> api_json_conn()
    |> put_req_header("authorization", "Bearer #{token}")
  end

  defp api_json_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end
end
