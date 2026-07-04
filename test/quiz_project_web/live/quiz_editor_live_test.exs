defmodule QuizProjectWeb.QuizEditorLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Quizzes

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, version} = Quizzes.create_draft_quiz(user)
    %{version: version}
  end

  test "autosave atualiza os dados básicos", %{conn: conn, version: version} do
    {:ok, view, _html} = live(conn, ~p"/quiz/#{version.id}/editar")

    view
    |> form("#quiz-form")
    |> render_change(%{
      "name" => "Quiz autosalvo",
      "description" => "descrição",
      "total_points" => "50",
      "question_order_mode" => "random"
    })

    updated = Quizzes.get_version!(version.id)
    assert updated.name == "Quiz autosalvo"
    assert Decimal.equal?(updated.total_points, Decimal.new(50))
    assert updated.question_order_mode == :random
  end

  test "adiciona pergunta verdadeiro/falso pelo modal", %{conn: conn, version: version} do
    {:ok, view, _html} = live(conn, ~p"/quiz/#{version.id}/editar")

    view |> element("#add-question") |> render_click()
    assert has_element?(view, "#question-modal")

    view
    |> form("#question-form")
    |> render_submit(%{
      "statement" => "O céu é azul?",
      "type" => "true_false",
      "true_false_answer" => "true",
      "editor_note" => "Depende do horário, mas em geral sim"
    })

    refute has_element?(view, "#question-modal")
    assert render(view) =~ "O céu é azul?"

    [question] = Quizzes.get_version_full!(version.id).questions
    assert question.type == :true_false
    assert question.true_false_answer == true
    assert question.editor_note =~ "Depende"
  end

  test "publicar sem nome nem questões lista erros", %{conn: conn, version: version} do
    {:ok, view, _html} = live(conn, ~p"/quiz/#{version.id}/editar")

    view |> element("#publish-quiz") |> render_click()

    html = render(view)
    assert has_element?(view, "#publish-errors")
    assert html =~ "precisa de um nome"
    assert html =~ "pelo menos uma questão"
  end

  test "publica quiz válido e navega para gerenciamento", %{
    conn: conn,
    version: version,
    user: user
  } do
    {:ok, _} = Quizzes.update_draft(version, %{name: "Quiz publicável"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "1+1=2?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, view, _html} = live(conn, ~p"/quiz/#{version.id}/editar")

    view |> element("#publish-quiz") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path == "/quiz/#{version.quiz_id}/gerenciar"

    assert Quizzes.get_version!(version.id).status == :published
  end

  test "versão publicada redireciona para gerenciamento", %{
    conn: conn,
    version: version,
    user: user
  } do
    {:ok, _} = Quizzes.update_draft(version, %{name: "Quiz"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "1+1=2?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, _} = Quizzes.publish(Quizzes.get_version!(version.id), user)

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/quiz/#{version.id}/editar")
    assert to == "/quiz/#{version.quiz_id}/gerenciar"
  end

  test "outro usuário não acessa o editor", %{version: version} do
    {:ok, other} =
      QuizProject.Accounts.register_user(%{email: "intruso@teste.com", password: "senha12345"},
        authorize?: false
      )

    conn = log_in_user(build_conn(), other)

    assert {:error, {:live_redirect, %{to: "/painel"}}} =
             live(conn, ~p"/quiz/#{version.id}/editar")
  end
end
