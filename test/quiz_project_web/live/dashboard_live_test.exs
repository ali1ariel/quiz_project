defmodule QuizProjectWeb.DashboardLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Attempts
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
    assert has_element?(view, "#download-format")
    assert has_element?(view, "#import-api-docs-link[href='/api/docs#usar-com-ia']")

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

  test "agrupa respondidos por quiz e versão com linha evolutiva", %{conn: conn, user: user} do
    participant = %{user: user, token: "token-dashboard"}

    # v1 com duas V/F (50 pts cada); primeira tentativa acerta só uma => 50%
    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz evolutivo"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q1?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, _q2} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q2?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published_v1} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    v1 = Quizzes.get_version_full!(published_v1.id)

    # duas tentativas na v1 (50% e depois 100%) para existir linha evolutiva
    {:ok, attempt1} = Attempts.start_attempt(v1, participant, "Eu mesmo")
    tf1 = Enum.find(attempt1.quiz_version.questions, &(&1.statement == "Q1?"))
    answer1 = Enum.find(attempt1.answers, &(&1.question_id == tf1.id))
    {:ok, _} = Attempts.save_answer(attempt1, answer1, tf1, %{"value" => true})
    {:ok, _} = Attempts.finalize(attempt1, force: true)

    {:ok, retry} = Attempts.start_attempt(v1, participant, "Eu mesmo")

    for question <- retry.quiz_version.questions do
      answer = Enum.find(retry.answers, &(&1.question_id == question.id))
      {:ok, _} = Attempts.save_answer(retry, answer, question, %{"value" => true})
    end

    {:ok, _} = Attempts.finalize(retry)

    # v2 muda uma questão; segunda tentativa acerta as duas => 100%
    quiz = Quizzes.get_quiz!(v1.quiz_id)
    {:ok, draft} = Quizzes.ensure_draft(quiz, user)

    q1_draft =
      Quizzes.get_version_full!(draft.id).questions
      |> Enum.find(&(&1.statement == "Q1?"))

    {:ok, _} =
      Quizzes.upsert_question(
        Quizzes.get_version!(draft.id),
        %{id: q1_draft.id, statement: "Q1 revisada?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published_v2} = Quizzes.publish(Quizzes.get_version!(draft.id), user)
    v2 = Quizzes.get_version_full!(published_v2.id)

    {:ok, attempt2} = Attempts.start_attempt(v2, participant, "Eu mesmo")

    for question <- attempt2.quiz_version.questions do
      answer = Enum.find(attempt2.answers, &(&1.question_id == question.id))
      {:ok, _} = Attempts.save_answer(attempt2, answer, question, %{"value" => true})
    end

    {:ok, _} = Attempts.finalize(attempt2)

    {:ok, view, _html} = live(conn, ~p"/painel")
    view |> element("#tab-answered") |> render_click()

    # um único card para o quiz, com subgrupos por versão
    assert has_element?(view, "#answered-quiz-#{quiz.id}")
    assert has_element?(view, "#answered-quiz-#{quiz.id}-v1")
    assert has_element?(view, "#answered-quiz-#{quiz.id}-v2")

    # versões não se misturam: linha evolutiva só na v1 (2 tentativas);
    # v2 tem uma tentativa e fica sem gráfico
    assert has_element?(view, "#evolution-#{quiz.id}-v1 svg path")
    refute has_element?(view, "#evolution-#{quiz.id}-v2")

    # link para a página de estatísticas do quiz
    assert has_element?(view, "#quiz-stats-#{quiz.id}")

    html = render(view)
    assert html =~ "50%"
    assert html =~ "100%"
    assert html =~ "Evolução das notas"
  end

  test "página de evolução compara respostas questão por questão", %{conn: conn, user: user} do
    participant = %{user: user, token: "token-evolucao"}

    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz evolução"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q1?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q2?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    v1 = Quizzes.get_version_full!(published.id)

    # 1ª tentativa: erra Q1 e acerta Q2; 2ª tentativa: acerta as duas
    {:ok, attempt1} = Attempts.start_attempt(v1, participant, "Eu mesmo")

    for question <- attempt1.quiz_version.questions do
      answer = Enum.find(attempt1.answers, &(&1.question_id == question.id))
      value = question.statement == "Q2?"
      {:ok, _} = Attempts.save_answer(attempt1, answer, question, %{"value" => value})
    end

    {:ok, _} = Attempts.finalize(attempt1)

    {:ok, attempt2} = Attempts.start_attempt(v1, participant, "Eu mesmo")

    for question <- attempt2.quiz_version.questions do
      answer = Enum.find(attempt2.answers, &(&1.question_id == question.id))
      {:ok, _} = Attempts.save_answer(attempt2, answer, question, %{"value" => true})
    end

    {:ok, _} = Attempts.finalize(attempt2)

    {:ok, view, html} = live(conn, ~p"/quiz/#{v1.quiz_id}/evolucao")

    assert html =~ "Quiz evolução"
    assert has_element?(view, "#evolution-v1")
    assert has_element?(view, "#evolution-chart-v1 svg path")

    # estatísticas da versão
    assert html =~ "Última nota"
    assert html =~ "Melhor nota"
    assert html =~ "Progresso"
    assert html =~ "+50%"

    # comparação por questão: Q1 evoluiu de incorreta para correta
    q1 = Enum.find(v1.questions, &(&1.statement == "Q1?"))
    q2 = Enum.find(v1.questions, &(&1.statement == "Q2?"))
    assert has_element?(view, "#evolution-v1-q#{q1.id}")
    assert html =~ "você evoluiu nesta questão"

    # Q2 sempre correta
    assert has_element?(view, "#evolution-v1-q#{q2.id}")
    assert html =~ "sempre correta"

    # as respostas em si, tentativa a tentativa
    assert html =~ "1ª tentativa"
    assert html =~ "2ª tentativa"
    assert html =~ "Resposta correta"

    # questões objetivas não têm avaliação de evolução por IA
    refute html =~ "Avaliar minha evolução com IA"
  end

  test "avalia com IA a evolução das respostas de uma questão discursiva", %{
    conn: conn,
    user: user
  } do
    participant = %{user: user, token: "token-discursiva"}

    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz discursivo"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{
          statement: "Explique a fotossíntese",
          type: :text,
          editor_note: "Conversão de luz solar em energia química pelas plantas"
        },
        [],
        user
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    v1 = Quizzes.get_version_full!(published.id)

    answers = [
      "Algo com plantas e sol.",
      "As plantas convertem luz solar em energia química por meio da fotossíntese."
    ]

    for text <- answers do
      {:ok, attempt} = Attempts.start_attempt(v1, participant, "Eu mesmo")
      question = hd(attempt.quiz_version.questions)
      answer = Enum.find(attempt.answers, &(&1.question_id == question.id))
      {:ok, _} = Attempts.save_answer(attempt, answer, question, %{"text" => text})
      {:ok, _} = Attempts.finalize(attempt)
    end

    {:ok, view, html} = live(conn, ~p"/quiz/#{v1.quiz_id}/evolucao")

    # as duas respostas aparecem na comparação
    assert html =~ "Algo com plantas e sol."
    assert html =~ "convertem luz solar em energia química"

    question = hd(v1.questions)
    assert has_element?(view, "#evaluate-question-#{question.id}")

    view |> element("#evaluate-question-#{question.id}") |> render_click()

    evaluated = render(view)
    assert has_element?(view, "#evaluation-question-#{question.id}")
    assert evaluated =~ "avaliação heurística local, sem IA externa"
    assert evaluated =~ "2 respostas suas para a mesma questão"
    refute has_element?(view, "#evaluate-question-#{question.id}")
  end

  test "painel notifica e atualiza ao vivo quando a correção termina", %{conn: conn, user: user} do
    participant = %{user: user, token: "token-notificacao"}

    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz notificado"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q1?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    v1 = Quizzes.get_version_full!(published.id)

    {:ok, attempt} = Attempts.start_attempt(v1, participant, "Eu mesmo")
    question = hd(attempt.quiz_version.questions)
    answer = Enum.find(attempt.answers, &(&1.question_id == question.id))
    {:ok, _} = Attempts.save_answer(attempt, answer, question, %{"value" => true})

    # tentativa entregue, correção ainda na fila
    attempt
    |> Ash.Changeset.for_update(:start_processing, %{}, authorize?: false)
    |> Ash.update!()

    {:ok, view, _html} = live(conn, ~p"/painel")
    view |> element("#tab-answered") |> render_click()

    # aparece como "corrigindo…" com link para acompanhar
    assert render(view) =~ "corrigindo…"
    assert render(view) =~ "Acompanhar correção"

    # correção termina em background → notificação fixa + lista ao vivo
    {:ok, finished} = Attempts.process_grading(attempt.id)

    updated = render(view)
    assert has_element?(view, "#notification-stack")
    assert updated =~ "Correção concluída"
    assert updated =~ "Quiz notificado"
    assert updated =~ "Clique aqui para ver o resultado"
    assert updated =~ "100%"
    refute updated =~ "corrigindo…"

    notification = user.id |> QuizProject.Notifications.list_unread() |> hd()

    # a notificação persiste ao navegar/remontar: aparece já no mount
    {:ok, view2, html2} = live(conn, ~p"/configuracoes")
    assert html2 =~ "Correção concluída"
    assert has_element?(view2, "#notification-#{notification.id}")

    # abrir leva ao resultado e marca como lida
    view2 |> element("#open-notification-#{notification.id}") |> render_click()
    assert_redirect(view2, "/tentativa/#{finished.id}/resultado")
    assert QuizProject.Notifications.list_unread(user.id) == []

    # dispensada/lida não volta mais
    {:ok, _view3, html3} = live(conn, ~p"/painel")
    refute html3 =~ "Correção concluída"
  end

  test "dispensar notificação a marca como lida sem navegar", %{conn: conn, user: user} do
    participant = %{user: user, token: "token-dispensa"}

    {:ok, version} = Quizzes.create_draft_quiz(user)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz dispensado"}, user)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Q1?", type: :true_false, true_false_answer: true},
        [],
        user
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), user)
    v1 = Quizzes.get_version_full!(published.id)

    {:ok, attempt} = Attempts.start_attempt(v1, participant, "Eu mesmo")
    {:ok, _} = Attempts.submit(attempt, force: true)

    [notification] = QuizProject.Notifications.list_unread(user.id)

    {:ok, view, _html} = live(conn, ~p"/painel")
    assert has_element?(view, "#notification-#{notification.id}")

    view |> element("#dismiss-notification-#{notification.id}") |> render_click()

    refute has_element?(view, "#notification-stack")
    assert QuizProject.Notifications.list_unread(user.id) == []
  end

  test "página de evolução sem tentativas redireciona ao painel", %{conn: conn, user: user} do
    {:ok, version} = Quizzes.create_draft_quiz(user)

    assert {:error, {:live_redirect, %{to: "/painel"}}} =
             live(conn, ~p"/quiz/#{version.quiz_id}/evolucao")
  end

  test "exige login", %{} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/entrar"}}} = live(conn, ~p"/painel")
  end
end
