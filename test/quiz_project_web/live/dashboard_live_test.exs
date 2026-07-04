defmodule QuizProjectWeb.DashboardLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Quizzes

  setup :register_and_log_in_user

  test "mostra abas e botões principais", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/painel")

    assert has_element?(view, "#tab-created")
    assert has_element?(view, "#tab-answered")
    assert has_element?(view, "#create-quiz")
    assert has_element?(view, "#open-import")
    assert has_element?(view, "span#desktop-nav-quizzes[aria-current=page]")
    assert has_element?(view, "a#desktop-nav-account")
    assert has_element?(view, "#appearance-control")
    assert has_element?(view, "#skin-select option[value=sobrio]")
    assert has_element?(view, "#skin-select option[value=aurora]")
    assert has_element?(view, "#skin-select option[value=classico]")
    refute has_element?(view, "#skin-select option[value=tatil]")
  end

  test "criar quiz navega para o editor do rascunho", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/painel")

    view |> element("#create-quiz") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/quiz/.+/editar$}
  end

  test "importa quiz válido e navega para o editor", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/painel")

    view |> element("#open-import") |> render_click()
    assert has_element?(view, "#import-modal")

    json =
      ~s({"nome": "Importado", "questoes": [{"enunciado": "2+2=4?", "tipo": "verdadeiro_falso", "resposta_verdadeiro_falso": true}]})

    # revisar: mostra a pré-visualização antes de importar
    html = view |> form("#import-form", %{"json" => json}) |> render_submit()
    assert has_element?(view, "#import-preview")
    assert html =~ "Importado"
    assert html =~ "1 questões"

    # confirmar: cria o rascunho e navega para o editor
    view |> element("#confirm-import") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/quiz/.+/editar$}
  end

  test "importa quiz por upload de arquivo JSON", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/painel")

    view |> element("#open-import") |> render_click()

    json =
      ~s({"nome": "Via arquivo", "questoes": [{"enunciado": "2+2=4?", "tipo": "verdadeiro_falso", "resposta_verdadeiro_falso": true}]})

    view
    |> file_input("#import-form", :json_file, [
      %{name: "quiz.json", content: json, type: "application/json"}
    ])
    |> render_upload("quiz.json")

    view |> form("#import-form", %{"json" => ""}) |> render_submit()
    assert has_element?(view, "#import-preview")

    view |> element("#confirm-import") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/quiz/.+/editar$}
  end

  test "JSON inválido mostra erros no modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/painel")

    view |> element("#open-import") |> render_click()

    html = view |> form("#import-form", %{"json" => ~s({"nome": ""})}) |> render_submit()

    assert html =~ "obrigatório"
    assert has_element?(view, "#import-modal")
  end

  test "lista quizzes criados e tentativas respondidas", %{conn: conn, user: user} do
    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, _} = Quizzes.update_draft(version, %{name: "Meu quiz listado"}, user)

    {:ok, view, html} = live(conn, ~p"/painel")

    assert html =~ "Meu quiz listado"
    assert has_element?(view, "#quiz-#{version.quiz_id}")

    # aba de respondidos vazia
    view |> element("#tab-answered") |> render_click()
    assert render(view) =~ "não respondeu nenhum quiz"
  end

  test "exige login", %{} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/entrar"}}} = live(conn, ~p"/painel")
  end
end
