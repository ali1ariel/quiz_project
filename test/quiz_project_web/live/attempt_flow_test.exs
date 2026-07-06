defmodule QuizProjectWeb.AttemptFlowTest do
  @moduledoc """
  Fluxo ponta a ponta: página pública → iniciar tentativa anônima → responder
  → confirmar (com e sem pendências) → resultado com correção → visão do
  criador somente leitura.
  """
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.Quizzes

  setup do
    {:ok, owner} =
      QuizProject.Accounts.register_user(%{email: "criador@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, version} = Quizzes.create_draft_quiz(owner)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz público"}, owner)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{
          statement: "O sol é uma estrela?",
          type: :true_false,
          true_false_answer: true,
          editor_note: "O sol é uma estrela de tipo espectral G."
        },
        [],
        owner
      )

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Capital do Brasil?", type: :single},
        [
          %{text: "Brasília", correct: true, position: 0},
          %{text: "Salvador", correct: false, position: 1}
        ],
        owner
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), owner)
    published = Quizzes.get_version_full!(published.id)

    quiz = Quizzes.get_quiz!(published.quiz_id)

    %{owner: owner, version: published, quiz: quiz}
  end

  defp start_attempt_with(conn, quiz) do
    {:ok, view, html} = live(conn, ~p"/q/#{quiz.public_slug}")
    assert html =~ "Quiz público"
    assert html =~ "Como prefere se identificar?"

    view
    |> form("#start-form", %{"display_identity" => "Participante X"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/tentativa/}

    {:ok, attempt_view, _html} = live(conn, path)
    {conn, attempt_view, path}
  end

  defp start_anonymous_attempt(quiz) do
    start_attempt_with(anonymous_session(build_conn()), quiz)
  end

  test "página pública de slug inexistente redireciona", %{} do
    conn = anonymous_session(build_conn())
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/q/nao-existe")
  end

  test "avisa sobre o cronômetro antes de iniciar e o exibe na tentativa", %{quiz: quiz} do
    conn = anonymous_session(build_conn())

    {:ok, public_view, _html} = live(conn, ~p"/q/#{quiz.public_slug}")
    assert has_element?(public_view, "#timer-notice")

    {_conn, attempt_view, _path} = start_attempt_with(conn, quiz)

    assert has_element?(attempt_view, "#attempt-timer[data-elapsed]")
    assert has_element?(attempt_view, "#attempt-timer button[aria-pressed='false']")
    assert has_element?(attempt_view, "#attempt-timer [data-timer-value].hidden")
  end

  test "fluxo completo com pendência e confirmação forçada", %{
    quiz: quiz,
    version: version,
    owner: owner
  } do
    # participante logado: o criador nunca pode ver os dados da conta dele
    {:ok, participant} =
      QuizProject.Accounts.register_user(
        %{email: "participante-real@teste.com", password: "senha12345"},
        authorize?: false
      )

    participant_conn = log_in_user(build_conn(), participant, "token-participante")
    {conn, view, _path} = start_attempt_with(participant_conn, quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))
    single = Enum.find(version.questions, &(&1.type == :single))

    # responde a V/F corretamente
    view |> element("#tf-#{tf.id}-true") |> render_click()
    assert render(view) =~ "1/2 respondidas"

    # marca a single para responder depois (fica pendente)
    view
    |> element("#attempt-question-#{single.id} button[phx-click='toggle_later']")
    |> render_click()

    # entregar abre direto o modal com as pendências e seus intervalos
    view |> element("#confirm-attempt") |> render_click()
    assert has_element?(view, "#confirm-modal")
    assert render(view) =~ "marcada(s) para responder depois"
    # a single é a questão 2 na ordem fixa
    assert has_element?(view, "#pending-later", "2")

    view |> element("#finalize-forced") |> render_click()

    {result_path, _flash} = assert_redirect(view)
    assert result_path =~ ~r{/resultado$}

    # resultado: correção aparece, pendente virou "não sei"
    {:ok, result_view, result_html} = live(conn, result_path)

    assert has_element?(result_view, "#final-score")
    assert has_element?(result_view, "#attempt-duration")
    assert result_html =~ "Resposta de referência"
    assert result_html =~ "O sol é uma estrela de tipo espectral G."
    assert result_html =~ "Não sei a resposta"
    assert result_html =~ "50%"

    # criador vê a mesma tela em modo somente leitura
    owner_conn = log_in_user(build_conn(), owner)
    {:ok, creator_view, creator_html} = live(owner_conn, result_path)

    assert has_element?(creator_view, "#creator-banner")
    assert creator_html =~ "Participante X"
    assert creator_html =~ "Resposta do participante"
    refute creator_html =~ "Sua resposta"
    refute creator_html =~ "participante-real@teste.com"
  end

  test "responder questão marcada para depois desmarca na interface", %{
    quiz: quiz,
    version: version
  } do
    {_conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))

    view |> element("#later-#{tf.id}") |> render_click()
    assert has_element?(view, "#later-#{tf.id}", "Desmarcar")

    view |> element("#tf-#{tf.id}-true") |> render_click()
    assert has_element?(view, "#later-#{tf.id}", "Responder depois")
  end

  test "formata intervalos de questões pendentes" do
    assert QuizProjectWeb.AttemptLive.format_ranges([3, 7, 8, 9, 30, 31, 32]) ==
             "3, 7 a 9, 30 a 32"

    assert QuizProjectWeb.AttemptLive.format_ranges([5]) == "5"
    assert QuizProjectWeb.AttemptLive.format_ranges([2, 1]) == "1 a 2"
    assert QuizProjectWeb.AttemptLive.format_ranges([]) == ""
  end

  test "limpar resposta oferece restauração", %{quiz: quiz, version: version} do
    {_conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))

    view |> element("#tf-#{tf.id}-true") |> render_click()
    assert has_element?(view, "#clear-#{tf.id}")

    view |> element("#clear-#{tf.id}") |> render_click()
    assert has_element?(view, "#restore-#{tf.id}")

    view |> element("#restore-#{tf.id}") |> render_click()
    refute has_element?(view, "#restore-#{tf.id}")
    assert render(view) =~ "1/2 respondidas"
  end

  test "não sei desabilita quando há resposta", %{quiz: quiz, version: version} do
    {_conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))

    assert has_element?(view, "#dont-know-#{tf.id}")

    view |> element("#tf-#{tf.id}-true") |> render_click()

    refute has_element?(view, "#dont-know-#{tf.id}")
    assert has_element?(view, "#clear-#{tf.id}")
  end

  test "sem pendências ainda pede confirmação antes de entregar", %{quiz: quiz, version: version} do
    {conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))
    single = Enum.find(version.questions, &(&1.type == :single))
    correct_option = Enum.find(single.options, & &1.correct)

    view |> element("#tf-#{tf.id}-true") |> render_click()
    view |> element("#single-#{single.id}-#{correct_option.id}") |> render_click()

    # mesmo tudo respondido, o modal aparece para confirmar a entrega
    view |> element("#confirm-attempt") |> render_click()
    assert has_element?(view, "#confirm-modal")
    view |> element("#finalize-forced") |> render_click()

    {result_path, _flash} = assert_redirect(view)
    {:ok, _result_view, result_html} = live(conn, result_path)

    assert result_html =~ "100%"
  end

  test "tentativa em andamento aparece para continuar na página pública", %{quiz: quiz} do
    {conn, _view, path} = start_anonymous_attempt(quiz)

    {:ok, view, _html} = live(conn, ~p"/q/#{quiz.public_slug}")

    assert has_element?(view, "#resume-box")
    assert has_element?(view, "a[href='#{path}']")
  end

  test "terceiro não acessa tentativa alheia", %{quiz: quiz} do
    {_conn, _view, path} = start_anonymous_attempt(quiz)

    other_conn = anonymous_session(build_conn(), "outro-token")
    assert {:error, {:live_redirect, %{to: "/"}}} = live(other_conn, path)
  end

  test "resultado de tentativa finalizada é público para quem tem o link", %{
    quiz: quiz,
    version: version
  } do
    {_conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))
    single = Enum.find(version.questions, &(&1.type == :single))
    correct_option = Enum.find(single.options, & &1.correct)

    view |> element("#tf-#{tf.id}-true") |> render_click()
    view |> element("#single-#{single.id}-#{correct_option.id}") |> render_click()
    view |> element("#confirm-attempt") |> render_click()
    view |> element("#finalize-forced") |> render_click()
    {result_path, _flash} = assert_redirect(view)

    # outra sessão anônima (sem o token do participante) enxerga o resultado
    other_conn = anonymous_session(build_conn(), "outro-token")
    {:ok, other_view, other_html} = live(other_conn, result_path)

    assert has_element?(other_view, "#final-score")
    assert has_element?(other_view, "#share-result")
    assert other_html =~ "Resposta do participante"
  end

  test "anulação é retroativa: re-corrige tentativas de versões anteriores", %{
    quiz: quiz,
    version: version,
    owner: owner
  } do
    {conn, view, _path} = start_anonymous_attempt(quiz)

    tf = Enum.find(version.questions, &(&1.type == :true_false))
    single = Enum.find(version.questions, &(&1.type == :single))
    correct_option = Enum.find(single.options, & &1.correct)

    # erra a V/F (correta é "verdadeiro") e acerta a única → 50%
    view |> element("#tf-#{tf.id}-false") |> render_click()
    view |> element("#single-#{single.id}-#{correct_option.id}") |> render_click()
    view |> element("#confirm-attempt") |> render_click()
    view |> element("#finalize-forced") |> render_click()
    {result_path, _flash} = assert_redirect(view)

    # antes da v2: 50%, questão ainda não anulada
    {:ok, _view, before_html} = live(conn, result_path)
    assert before_html =~ "50% de aproveitamento"
    refute before_html =~ "annulled-#{tf.id}"

    # cria e publica a v2, anulando a questão V/F nela
    {:ok, draft} = Quizzes.ensure_draft(quiz, owner)
    {:ok, v2} = Quizzes.publish(Quizzes.get_version!(draft.id), owner)
    v2 = Quizzes.get_version_full!(v2.id)
    v2_tf = Enum.find(v2.questions, &(&1.type == :true_false))
    {:ok, _} = Quizzes.annul_question(v2_tf, "Enunciado ambíguo", owner)

    # a anulação propagou para a questão da v1 (mesma identity_key) e a nota
    # da tentativa foi persistida: sobe para 100%
    tf_v1 = Quizzes.get_question!(tf.id)
    assert tf_v1.annulled
    assert tf_v1.annulled_reason == "Enunciado ambíguo"

    {:ok, _view, html} = live(conn, result_path)
    assert html =~ "annulled-#{tf.id}"
    assert html =~ "Questão anulada — pontuação integral concedida a todos"
    assert html =~ "Enunciado ambíguo"
    assert html =~ "100% de aproveitamento"
  end
end
