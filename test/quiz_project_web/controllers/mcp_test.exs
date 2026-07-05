defmodule QuizProjectWeb.McpTest do
  use QuizProjectWeb.ConnCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Accounts.ApiToken

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{email: "mcp-owner@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "mcp-other@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, token, _record} = Accounts.issue_api_token(user, %{name: "MCP"})
    {:ok, other_token, _record} = Accounts.issue_api_token(other, %{name: "Outro"})

    %{
      conn: api_conn(conn, token),
      anonymous_conn: api_json_conn(build_conn()),
      other_conn: api_conn(build_conn(), other_token),
      user: user
    }
  end

  test "exige Bearer token", %{anonymous_conn: conn} do
    conn = post(conn, ~p"/api/mcp", rpc_body("tools/list"))
    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "responde initialize com a versão negociada e as capacidades", %{conn: conn} do
    response =
      conn
      |> post(
        ~p"/api/mcp",
        rpc_body("initialize", %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "teste", "version" => "1.0"}
        })
      )
      |> json_response(200)

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "protocolVersion" => "2025-06-18",
               "capabilities" => %{"tools" => %{}},
               "serverInfo" => %{"name" => "quiz_project"}
             }
           } = response
  end

  test "usa a versão padrão quando a solicitada não é suportada", %{conn: conn} do
    response =
      conn
      |> post(~p"/api/mcp", rpc_body("initialize", %{"protocolVersion" => "1999-01-01"}))
      |> json_response(200)

    assert response["result"]["protocolVersion"] == "2025-06-18"
  end

  test "aceita notificações com 202 e sem corpo", %{conn: conn} do
    conn =
      post(conn, ~p"/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      })

    assert response(conn, 202) == ""
  end

  test "lista as ferramentas espelhando a API", %{conn: conn} do
    response = conn |> post(~p"/api/mcp", rpc_body("tools/list")) |> json_response(200)

    names = Enum.map(response["result"]["tools"], & &1["name"])

    assert names == [
             "create_question",
             "create_quiz",
             "create_quiz_draft",
             "delete_question",
             "get_quiz",
             "get_quiz_version",
             "import_quiz",
             "list_quizzes",
             "publish_quiz_version",
             "set_quiz_active",
             "update_question",
             "update_quiz_version",
             "validate_quiz_version"
           ]

    assert Enum.all?(response["result"]["tools"], fn tool ->
             is_binary(tool["description"]) and tool["inputSchema"]["type"] == "object"
           end)
  end

  test "retorna erros JSON-RPC para método e ferramenta desconhecidos", %{conn: conn} do
    response = conn |> post(~p"/api/mcp", rpc_body("resources/list")) |> json_response(200)
    assert %{"error" => %{"code" => -32601}} = response

    response =
      conn
      |> recycle()
      |> post(~p"/api/mcp", rpc_body("tools/call", %{"name" => "inexistente"}))
      |> json_response(200)

    assert %{"error" => %{"code" => -32602}} = response
  end

  test "rejeita lotes JSON-RPC", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/mcp", Jason.encode!([rpc_body("ping")]))

    assert %{"error" => %{"code" => -32600}} = json_response(conn, 200)
  end

  test "GET e DELETE retornam 405", %{conn: conn} do
    conn = get(conn, ~p"/api/mcp")
    assert response(conn, 405)
    assert get_resp_header(conn, "allow") == ["POST"]
  end

  test "cria, edita, valida e publica um quiz via tools/call", %{conn: conn} do
    created = call_tool(conn, "create_quiz", %{"name" => "Quiz via MCP", "total_points" => 50})
    refute created["isError"]

    version = created["structuredContent"]
    assert version["name"] == "Quiz via MCP"
    assert version["status"] == "draft"
    version_id = version["id"]
    quiz_id = version["quiz_id"]

    listed = call_tool(conn, "list_quizzes")
    assert [%{"id" => ^quiz_id}] = listed["structuredContent"]["quizzes"]

    updated =
      call_tool(conn, "update_quiz_version", %{
        "version_id" => version_id,
        "description" => "Editado via MCP"
      })

    assert updated["structuredContent"]["description"] == "Editado via MCP"

    question =
      call_tool(conn, "create_question", %{
        "version_id" => version_id,
        "statement" => "O MCP espelha a API?",
        "type" => "true_false",
        "true_false_answer" => true
      })

    assert question["structuredContent"]["true_false_answer"]

    validated = call_tool(conn, "validate_quiz_version", %{"version_id" => version_id})
    assert %{"valid" => true, "errors" => []} = validated["structuredContent"]

    published = call_tool(conn, "publish_quiz_version", %{"version_id" => version_id})
    assert published["structuredContent"]["status"] == "published"

    activated = call_tool(conn, "set_quiz_active", %{"quiz_id" => quiz_id, "active" => true})
    assert activated["structuredContent"]["active"]
  end

  test "atualiza e remove questões de um rascunho", %{conn: conn} do
    created = call_tool(conn, "create_quiz", %{"name" => "Quiz de questões"})
    version_id = created["structuredContent"]["id"]

    question =
      call_tool(conn, "create_question", %{
        "version_id" => version_id,
        "statement" => "Escolha uma",
        "type" => "single",
        "options" => [
          %{"text" => "Certa", "correct" => true, "position" => 1},
          %{"text" => "Errada", "correct" => false, "position" => 2}
        ]
      })

    question_id = question["structuredContent"]["id"]
    assert length(question["structuredContent"]["options"]) == 2

    updated =
      call_tool(conn, "update_question", %{
        "question_id" => question_id,
        "statement" => "Escolha a correta"
      })

    assert updated["structuredContent"]["statement"] == "Escolha a correta"
    assert length(updated["structuredContent"]["options"]) == 2

    deleted = call_tool(conn, "delete_question", %{"question_id" => question_id})
    assert deleted["structuredContent"]["deleted"]

    reloaded = call_tool(conn, "get_quiz_version", %{"version_id" => version_id})
    assert reloaded["structuredContent"]["questions"] == []
  end

  test "importa o formato JSON existente", %{conn: conn} do
    imported =
      call_tool(conn, "import_quiz", %{
        "data" => %{
          "nome" => "Quiz importado via MCP",
          "questoes" => [
            %{
              "enunciado" => "O MCP importa?",
              "tipo" => "verdadeiro_falso",
              "resposta_verdadeiro_falso" => true
            }
          ]
        }
      })

    refute imported["isError"]
    assert imported["structuredContent"]["name"] == "Quiz importado via MCP"
    assert length(imported["structuredContent"]["questions"]) == 1
  end

  test "não expõe quizzes de outro usuário", %{conn: conn, other_conn: other_conn} do
    created = call_tool(conn, "create_quiz", %{"name" => "Privado"})
    quiz_id = created["structuredContent"]["quiz_id"]

    result = call_tool(other_conn, "get_quiz", %{"quiz_id" => quiz_id})
    assert result["isError"]
    assert result["structuredContent"]["error"]["code"] == "not_found"
  end

  test "retorna erro de domínio ao editar versão publicada", %{conn: conn} do
    created = call_tool(conn, "create_quiz", %{"name" => "Quiz travado"})
    version_id = created["structuredContent"]["id"]

    call_tool(conn, "create_question", %{
      "version_id" => version_id,
      "statement" => "Pergunta única",
      "type" => "text"
    })

    call_tool(conn, "publish_quiz_version", %{"version_id" => version_id})

    result =
      call_tool(conn, "update_quiz_version", %{"version_id" => version_id, "name" => "Não pode"})

    assert result["isError"]
    assert result["structuredContent"]["error"]["code"] == "validation_error"
  end

  test "sinaliza argumentos obrigatórios ausentes", %{conn: conn} do
    result = call_tool(conn, "get_quiz", %{})

    assert result["isError"]

    assert %{"code" => "validation_error", "details" => [details]} =
             result["structuredContent"]["error"]

    assert details =~ "quiz_id"
  end

  test "exige o escopo da ferramenta", %{user: user} do
    raw = "quiz_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    hash = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

    ApiToken
    |> Ash.Changeset.for_create(
      :create,
      %{user_id: user.id, name: "Somente leitura", token_hash: hash, scopes: ["quizzes:read"]},
      authorize?: false
    )
    |> Ash.create!()

    read_only = api_conn(build_conn(), raw)

    listed = call_tool(read_only, "list_quizzes")
    refute listed["isError"]

    denied = call_tool(read_only, "create_quiz", %{"name" => "Sem escopo"})
    assert denied["isError"]

    assert %{"code" => "insufficient_scope", "required_scope" => "quizzes:write"} =
             denied["structuredContent"]["error"]
  end

  defp call_tool(conn, name, args \\ %{}) do
    response =
      conn
      |> recycle()
      |> post(~p"/api/mcp", rpc_body("tools/call", %{"name" => name, "arguments" => args}))
      |> json_response(200)

    assert response["jsonrpc"] == "2.0"
    response["result"]
  end

  defp rpc_body(method, params \\ %{}) do
    %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
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
