defmodule QuizProjectWeb.PageControllerTest do
  use QuizProjectWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Crie e responda quizzes"
    assert html =~ "images/logo.png"
  end

  test "GET /api/docs", %{conn: conn} do
    conn = get(conn, ~p"/api/docs")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#api-docs") |> Enum.any?()
    assert document |> LazyHTML.query("#usar-com-ia") |> Enum.any?()

    assert document
           |> LazyHTML.query("#api-docs-open-token-settings[href='/settings?tab=tokens']")
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
    assert document |> LazyHTML.query("#endpoint-create-product table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-get-metrics table") |> Enum.any?()
    assert document |> LazyHTML.query("#endpoint-study-import table") |> Enum.any?()
    assert document |> LazyHTML.query("#erros table") |> Enum.any?()
  end

  test "GET /privacy é pública e menciona o uso de dados do Google Calendar", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    html = html_response(conn, 200)

    assert html =~ "Política de Privacidade"
    assert html =~ "Google Calendar API"
    assert html =~ "alisson.ariel@gmail.com"
  end

  test "GET /terms é pública e referencia a Política de Privacidade", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    html = html_response(conn, 200)

    assert html =~ "Termos de Serviço"
    assert html =~ ~s(href="/privacy")
  end

  test "rodapé com links de Privacidade e Termos aparece em qualquer página", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(href="/privacy")
    assert html =~ ~s(href="/terms")
  end
end
