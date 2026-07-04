defmodule QuizProjectWeb.QuizManageLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.{Attempts, Quizzes}

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz gerenciado"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "1+1=2?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    quiz = Quizzes.get_quiz!(published.quiz_id)

    %{quiz: quiz, published: Quizzes.get_version_full!(published.id)}
  end

  test "mostra link público e abas", %{conn: conn, quiz: quiz} do
    {:ok, view, html} = live(conn, ~p"/quiz/#{quiz.id}/gerenciar")

    assert html =~ quiz.public_slug
    assert has_element?(view, "#manage-tab-attempts")
    assert has_element?(view, "#manage-tab-questions")
    assert has_element?(view, "#manage-tab-versions")
  end

  test "anula questão com motivo", %{conn: conn, quiz: quiz, published: published} do
    [question] = published.questions

    {:ok, view, _html} = live(conn, ~p"/quiz/#{quiz.id}/gerenciar")

    view |> element("#manage-tab-questions") |> render_click()
    view |> element("#annul-#{question.id}") |> render_click()

    assert has_element?(view, "#annul-modal")

    view
    |> form("#annul-form", %{"reason" => "Enunciado com duas interpretações"})
    |> render_submit()

    html = render(view)
    assert html =~ "anulada"
    assert html =~ "Enunciado com duas interpretações"

    annulled = Quizzes.get_question!(question.id)
    assert annulled.annulled
  end

  test "lista tentativas finalizadas com identificação", %{conn: conn, quiz: quiz, published: published} do
    {:ok, attempt} =
      Attempts.start_attempt(
        published,
        %{user: nil, token: "token-visitante"},
        "Visitante Anônimo"
      )

    {:ok, _} = Attempts.finalize(attempt, force: true)

    {:ok, view, _html} = live(conn, ~p"/quiz/#{quiz.id}/gerenciar")

    assert render(view) =~ "Visitante Anônimo"
    assert has_element?(view, "#view-attempt-#{attempt.id}")
  end

  test "histórico mostra changelog", %{conn: conn, quiz: quiz} do
    {:ok, view, _html} = live(conn, ~p"/quiz/#{quiz.id}/gerenciar")

    view |> element("#manage-tab-versions") |> render_click()

    assert render(view) =~ "Primeira versão publicada"
  end

  test "quiz sem publicação redireciona ao painel", %{conn: conn, user: user} do
    {:ok, draft} = Quizzes.create_draft_quiz(user)

    assert {:error, {:live_redirect, %{to: "/painel"}}} =
             live(conn, ~p"/quiz/#{draft.quiz_id}/gerenciar")
  end
end
