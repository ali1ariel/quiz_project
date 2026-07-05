defmodule QuizProjectWeb.PageControllerTest do
  use QuizProjectWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Crie e responda quizzes"
  end

  test "GET /api/docs", %{conn: conn} do
    conn = get(conn, ~p"/api/docs")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#api-docs") |> Enum.any?()
    assert document |> LazyHTML.query("#usar-com-ia") |> Enum.any?()

    assert document
           |> LazyHTML.query("#api-docs-open-token-settings[href='/configuracoes?tab=tokens']")
           |> Enum.any?()

    assert document |> LazyHTML.query("#api-ai-prompt") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-mcp table") |> Enum.any?()
    assert document |> LazyHTML.query("#ai-panel-claude") |> Enum.any?()
    assert document |> LazyHTML.query("#ai-panel-chatgpt") |> Enum.any?()
    assert document |> LazyHTML.query("#openapi-schema-url") |> Enum.any?()
    assert document |> LazyHTML.query("#ai-panel-gemini") |> Enum.any?()
    assert document |> LazyHTML.query("input#ai-tab-claude[checked]") |> Enum.any?()
    assert document |> LazyHTML.query("#contratos table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-create-quiz table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-import-quiz table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-update-version table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-create-question table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-update-question table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-validate-version pre") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-publish-version") |> Enum.any?()
    assert document |> LazyHTML.query("#erros table") |> Enum.any?()
  end
end
