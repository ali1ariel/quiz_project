defmodule QuizProject.AttemptsTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Attempts
  alias QuizProject.Quizzes

  setup do
    {:ok, owner} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, participant_user} =
      Accounts.register_user(%{email: "participante@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{
      owner: owner,
      logged: %{user: participant_user, token: "token-logado"},
      anonymous: %{user: nil, token: "token-anonimo"}
    }
  end

  # Quiz publicado com 4 questões: V/F, única, múltipla (parcial) e discursiva.
  # Nota total 100, pesos iguais => 25 pontos cada.
  defp published_quiz(owner) do
    {:ok, version} = Quizzes.create_draft_quiz(owner)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz completo"}, owner)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "O sol é uma estrela?", type: :true_false, true_false_answer: true},
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

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Quais são números pares?", type: :multiple, allow_partial_credit: true},
        [
          %{text: "2", correct: true, position: 0},
          %{text: "3", correct: false, position: 1},
          %{text: "4", correct: true, position: 2},
          %{text: "6", correct: true, position: 3}
        ],
        owner
      )

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{
          statement: "Explique a fotossíntese",
          type: :text,
          editor_note: "Deve citar conversão de luz solar em energia química pelas plantas"
        },
        [],
        owner
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), owner)
    Quizzes.get_version_full!(published.id)
  end

  defp question_by_type(attempt, type) do
    Enum.find(attempt.quiz_version.questions, &(&1.type == type))
  end

  defp answer_for(attempt, question) do
    Enum.find(attempt.answers, &(&1.question_id == question.id))
  end

  defp option_key(question, text) do
    Enum.find(question.options, &(&1.text == text)).identity_key
  end

  defp reload(attempt), do: Attempts.get_attempt_full!(attempt.id)

  describe "início de tentativa" do
    test "cria com ordem fixa salva e respostas vazias", %{owner: owner, anonymous: anon} do
      version = published_quiz(owner)

      {:ok, attempt} = Attempts.start_attempt(version, anon, "Fulano")

      assert attempt.status == :in_progress
      assert attempt.display_identity == "Fulano"
      assert attempt.participant_token == "token-anonimo"
      assert length(attempt.question_order) == 4
      assert length(attempt.answers) == 4
      assert Enum.all?(attempt.answers, &(&1.state == :unanswered))

      # ordem fixa segue as posições
      expected = version.questions |> Enum.sort_by(& &1.position) |> Enum.map(& &1.id)
      assert attempt.question_order == expected
    end

    test "exige identificação", %{owner: owner, anonymous: anon} do
      version = published_quiz(owner)

      assert {:error, %Ash.Error.Invalid{}} = Attempts.start_attempt(version, anon, nil)
    end

    test "não inicia em rascunho", %{owner: owner, anonymous: anon} do
      {:ok, draft} = Quizzes.create_draft_quiz(owner)

      assert {:error, :not_published} = Attempts.start_attempt(draft, anon, "Fulano")
    end

    test "find_in_progress localiza tentativa aberta", %{owner: owner, logged: logged} do
      version = published_quiz(owner)

      assert Attempts.find_in_progress(version, logged) == nil

      {:ok, attempt} = Attempts.start_attempt(version, logged, "Beltrano")

      found = Attempts.find_in_progress(version, logged)
      assert found.id == attempt.id
    end
  end

  describe "estados de resposta" do
    setup %{owner: owner, anonymous: anon} do
      version = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(version, anon, "Fulano")
      %{version: version, attempt: attempt}
    end

    test "salva resposta de cada tipo", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      single = question_by_type(attempt, :single)
      multiple = question_by_type(attempt, :multiple)
      text = question_by_type(attempt, :text)

      {:ok, _} = Attempts.save_answer(attempt, answer_for(attempt, tf), tf, %{"value" => true})

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, single), single, %{
          "option" => option_key(single, "Brasília")
        })

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, multiple), multiple, %{
          "options" => [option_key(multiple, "2"), option_key(multiple, "4")]
        })

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, text), text, %{
          "text" => "As plantas convertem luz solar em energia química"
        })

      attempt = reload(attempt)
      assert Enum.all?(attempt.answers, &(&1.state == :answered))
    end

    test "rejeita payload inválido", %{attempt: attempt} do
      single = question_by_type(attempt, :single)
      answer = answer_for(attempt, single)

      assert {:error, :invalid_payload} =
               Attempts.save_answer(attempt, answer, single, %{"option" => "chave-inexistente"})

      text = question_by_type(attempt, :text)

      assert {:error, :invalid_payload} =
               Attempts.save_answer(attempt, answer_for(attempt, text), text, %{"text" => "   "})
    end

    test "não sei só sem resposta preenchida; é alternável", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      answer = answer_for(attempt, tf)

      {:ok, answer} = Attempts.toggle_dont_know(attempt, answer)
      assert answer.state == :dont_know

      {:ok, answer} = Attempts.toggle_dont_know(attempt, answer)
      assert answer.state == :unanswered

      {:ok, answer} = Attempts.save_answer(attempt, answer, tf, %{"value" => false})
      assert {:error, :has_answer} = Attempts.toggle_dont_know(attempt, answer)
    end

    test "limpar guarda backup e restaurar recupera", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      answer = answer_for(attempt, tf)

      {:ok, answer} = Attempts.save_answer(attempt, answer, tf, %{"value" => true})
      {:ok, answer} = Attempts.clear_answer(attempt, answer)

      assert answer.state == :unanswered
      assert answer.payload == nil
      assert answer.cleared_backup == %{"value" => true}

      {:ok, answer} = Attempts.restore_answer(attempt, answer)
      assert answer.state == :answered
      assert answer.payload == %{"value" => true}
      assert answer.cleared_backup == nil

      assert {:error, :nothing_to_restore} = Attempts.restore_answer(attempt, answer)
    end

    test "marcar para depois é alternável", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      answer = answer_for(attempt, tf)

      {:ok, answer} = Attempts.toggle_marked_later(attempt, answer)
      assert answer.marked_later

      {:ok, answer} = Attempts.toggle_marked_later(attempt, answer)
      refute answer.marked_later
    end

    test "responder desmarca 'responder depois'; remarcar mantém a resposta", %{
      attempt: attempt
    } do
      tf = question_by_type(attempt, :true_false)
      answer = answer_for(attempt, tf)

      {:ok, answer} = Attempts.toggle_marked_later(attempt, answer)
      assert answer.marked_later

      # responder desmarca automaticamente
      {:ok, answer} = Attempts.save_answer(attempt, answer, tf, %{"value" => true})
      refute answer.marked_later
      assert answer.state == :answered

      # remarcar não apaga a resposta já dada
      {:ok, answer} = Attempts.toggle_marked_later(attempt, answer)
      assert answer.marked_later
      assert answer.state == :answered
      assert answer.payload == %{"value" => true}
    end
  end

  describe "finalização e correção" do
    setup %{owner: owner, anonymous: anon} do
      version = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(version, anon, "Fulano")
      %{version: version, attempt: attempt}
    end

    test "com pendências exige confirmação e converte para não sei", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      single = question_by_type(attempt, :single)

      {:ok, _} = Attempts.save_answer(attempt, answer_for(attempt, tf), tf, %{"value" => true})
      {:ok, _} = Attempts.toggle_marked_later(attempt, answer_for(attempt, single))

      assert {:error, {:pending, %{unanswered: 2, later: 1}}} = Attempts.finalize(attempt)

      {:ok, finished} = Attempts.finalize(attempt, force: true)

      assert finished.status == :finished

      converted = answer_for(finished, single)
      assert converted.state == :dont_know

      # não sei vale zero; V/F correta vale 25
      assert Decimal.equal?(converted.score, Decimal.new(0))
      assert Decimal.equal?(answer_for(finished, tf).score, Decimal.new(25))
    end

    test "tentativa finalizada nunca mais é editável", %{attempt: attempt} do
      {:ok, finished} = Attempts.finalize(attempt, force: true)

      tf = question_by_type(finished, :true_false)

      assert {:error, :finished} =
               Attempts.save_answer(finished, answer_for(finished, tf), tf, %{"value" => true})

      assert {:error, :finished} = Attempts.finalize(finished, force: true)
    end

    test "corrige objetivas: tudo certo dá nota máxima", %{attempt: attempt} do
      tf = question_by_type(attempt, :true_false)
      single = question_by_type(attempt, :single)
      multiple = question_by_type(attempt, :multiple)
      text = question_by_type(attempt, :text)

      {:ok, _} = Attempts.save_answer(attempt, answer_for(attempt, tf), tf, %{"value" => true})

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, single), single, %{
          "option" => option_key(single, "Brasília")
        })

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, multiple), multiple, %{
          "options" => [
            option_key(multiple, "2"),
            option_key(multiple, "4"),
            option_key(multiple, "6")
          ]
        })

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, text), text, %{
          "text" => "Deve citar conversão de luz solar em energia química pelas plantas"
        })

      {:ok, finished} = Attempts.finalize(attempt)

      assert Decimal.equal?(answer_for(finished, tf).score, Decimal.new(25))
      assert Decimal.equal?(answer_for(finished, single).score, Decimal.new(25))
      assert Decimal.equal?(answer_for(finished, multiple).score, Decimal.new(25))

      # discursiva idêntica à referência: 100% => 25 pontos
      text_answer = answer_for(finished, text)
      assert text_answer.ai_percent == 100
      assert Decimal.equal?(text_answer.score, Decimal.new(25))
      refute text_answer.ai_reference_generated

      assert Decimal.equal?(finished.score, Decimal.new(100))
      assert Decimal.equal?(finished.max_score, Decimal.new(100))
    end

    test "múltipla: parcial proporcional sem incorretas", %{attempt: attempt} do
      multiple = question_by_type(attempt, :multiple)

      # 2 de 3 corretas, nenhuma incorreta => 2/3 de 25
      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, multiple), multiple, %{
          "options" => [option_key(multiple, "2"), option_key(multiple, "4")]
        })

      {:ok, finished} = Attempts.finalize(attempt, force: true)

      expected = Decimal.div(Decimal.mult(Decimal.new(25), Decimal.new(2)), Decimal.new(3))
      assert Decimal.equal?(answer_for(finished, multiple).score, expected)
    end

    test "múltipla: qualquer incorreta zera a questão", %{attempt: attempt} do
      multiple = question_by_type(attempt, :multiple)

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, multiple), multiple, %{
          "options" => [
            option_key(multiple, "2"),
            option_key(multiple, "4"),
            option_key(multiple, "3")
          ]
        })

      {:ok, finished} = Attempts.finalize(attempt, force: true)

      assert Decimal.equal?(answer_for(finished, multiple).score, Decimal.new(0))
    end

    test "discursiva sem referência do criador usa referência gerada", %{
      owner: owner,
      anonymous: anon
    } do
      {:ok, version} = Quizzes.create_draft_quiz(owner)
      {:ok, version} = Quizzes.update_draft(version, %{name: "Só discursiva"}, owner)

      {:ok, _} =
        Quizzes.upsert_question(
          version,
          %{statement: "O que é gravidade?", type: :text},
          [],
          owner
        )

      {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), owner)
      {:ok, attempt} = Attempts.start_attempt(published, anon, "Fulano")

      question = question_by_type(attempt, :text)

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, question), question, %{
          "text" => "É a força que atrai os corpos"
        })

      {:ok, finished} = Attempts.finalize(attempt)

      graded = answer_for(finished, question)
      assert graded.ai_reference_generated
      assert is_binary(graded.ai_reference)
      assert is_binary(graded.ai_feedback)
    end

    test "questão anulada dá pontuação integral independente da resposta", %{
      owner: owner,
      version: version,
      attempt: attempt
    } do
      tf = question_by_type(attempt, :true_false)

      # responde errado
      {:ok, _} = Attempts.save_answer(attempt, answer_for(attempt, tf), tf, %{"value" => false})

      # criador anula a questão na versão publicada
      question = Enum.find(version.questions, &(&1.id == tf.id))
      {:ok, _} = Quizzes.annul_question(question, "Questão ambígua", owner)

      {:ok, finished} = Attempts.finalize(attempt, force: true)

      assert Decimal.equal?(answer_for(finished, tf).score, Decimal.new(25))
    end
  end

  describe "reaproveitamento entre versões" do
    test "importa respostas compatíveis e não as incompatíveis", %{owner: owner, logged: logged} do
      v1 = published_quiz(owner)

      {:ok, attempt} = Attempts.start_attempt(v1, logged, "Beltrano")

      tf = question_by_type(attempt, :true_false)
      single = question_by_type(attempt, :single)

      {:ok, _} = Attempts.save_answer(attempt, answer_for(attempt, tf), tf, %{"value" => true})

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, single), single, %{
          "option" => option_key(single, "Brasília")
        })

      {:ok, _} = Attempts.finalize(attempt, force: true)

      # nova versão: muda o enunciado da V/F (quebra), mantém a single
      quiz = Quizzes.get_quiz!(v1.quiz_id)
      {:ok, draft} = Quizzes.ensure_draft(quiz, owner)

      draft_tf = Enum.find(draft.questions, &(&1.type == :true_false))

      {:ok, _} =
        Quizzes.upsert_question(
          draft,
          %{id: draft_tf.id, statement: "O sol é um planeta?", true_false_answer: false},
          [],
          owner
        )

      {:ok, v2} = Quizzes.publish(Quizzes.get_version!(draft.id), owner)
      v2 = Quizzes.get_version_full!(v2.id)

      {:ok, new_attempt} = Attempts.start_attempt(v2, logged, "Beltrano")

      new_single = question_by_type(new_attempt, :single)
      new_tf = question_by_type(new_attempt, :true_false)

      imported = answer_for(new_attempt, new_single)
      assert imported.state == :answered
      assert imported.imported_from_previous
      assert imported.payload["option"] == option_key(new_single, "Brasília")

      not_imported = answer_for(new_attempt, new_tf)
      assert not_imported.state == :unanswered
      refute not_imported.imported_from_previous

      # editar a resposta importada remove a pill
      {:ok, edited} =
        Attempts.save_answer(new_attempt, imported, new_single, %{
          "option" => option_key(new_single, "Salvador")
        })

      refute edited.imported_from_previous
    end

    test "questão anulada não é reaproveitada", %{owner: owner, logged: logged} do
      v1 = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(v1, logged, "Beltrano")

      single = question_by_type(attempt, :single)

      {:ok, _} =
        Attempts.save_answer(attempt, answer_for(attempt, single), single, %{
          "option" => option_key(single, "Brasília")
        })

      {:ok, _} = Attempts.finalize(attempt, force: true)

      # anula a questão na v1 e publica v2 sem mudanças estruturais
      v1_single = Enum.find(Quizzes.get_version_full!(v1.id).questions, &(&1.type == :single))
      {:ok, _} = Quizzes.annul_question(v1_single, "Anulada após tentativa", owner)

      quiz = Quizzes.get_quiz!(v1.quiz_id)
      {:ok, draft} = Quizzes.ensure_draft(quiz, owner)

      # remove a anulação herdada no rascunho (questão "reimplementada")
      draft_single = Enum.find(draft.questions, &(&1.type == :single))

      {:ok, _} =
        Quizzes.upsert_question(
          draft,
          %{id: draft_single.id, annulled: false, annulled_reason: nil},
          Enum.map(
            draft_single.options,
            &%{id: &1.id, text: &1.text, correct: &1.correct, position: &1.position}
          ),
          owner
        )

      {:ok, v2} = Quizzes.publish(Quizzes.get_version!(draft.id), owner)
      v2 = Quizzes.get_version_full!(v2.id)

      {:ok, new_attempt} = Attempts.start_attempt(v2, logged, "Beltrano")

      new_single = question_by_type(new_attempt, :single)
      refute answer_for(new_attempt, new_single).imported_from_previous
    end
  end

  describe "adoção de tentativas anônimas" do
    test "vincula tentativas do token ao usuário no login", %{owner: owner, anonymous: anon} do
      version = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(version, anon, "Anônimo")

      {:ok, user} =
        Accounts.register_user(%{email: "logou@depois.com", password: "senha12345"},
          authorize?: false
        )

      :ok = Attempts.adopt_anonymous_attempts(user, "token-anonimo")

      adopted = Attempts.get_attempt_full!(attempt.id)
      assert adopted.user_id == user.id

      assert [answered] = Attempts.list_answered(user) |> Enum.filter(&(&1.id == attempt.id))
      assert answered.display_identity == "Anônimo"
    end
  end

  describe "autorização e visão do criador" do
    test "participante acessa por conta ou token; terceiros não", %{
      owner: owner,
      logged: logged,
      anonymous: anon
    } do
      version = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(version, anon, "Anônimo")

      assert :ok = Attempts.authorize_participant(attempt, anon)
      assert {:error, :unauthorized} = Attempts.authorize_participant(attempt, logged)
    end

    test "criador lista tentativas finalizadas com identificação escolhida", %{
      owner: owner,
      logged: logged
    } do
      version = published_quiz(owner)
      {:ok, attempt} = Attempts.start_attempt(version, logged, "Apelido Escolhido")
      {:ok, _} = Attempts.finalize(attempt, force: true)

      quiz = Quizzes.get_quiz!(version.quiz_id)

      {:ok, [listed]} = Attempts.list_attempts_for_quiz(quiz, owner)
      assert listed.display_identity == "Apelido Escolhido"

      assert {:error, :unauthorized} = Attempts.list_attempts_for_quiz(quiz, logged.user)
    end
  end

  describe "status de página" do
    setup do
      %{
        unanswered: %{state: :unanswered, marked_later: false},
        later: %{state: :unanswered, marked_later: true},
        answered: %{state: :answered, marked_later: false},
        answered_later: %{state: :answered, marked_later: true},
        dont_know: %{state: :dont_know, marked_later: false}
      }
    end

    test "antes da validação: neutro para incompleta, sem vermelho", ctx do
      assert Attempts.page_status([ctx.unanswered, ctx.answered]) == :neutral
      assert Attempts.page_status([ctx.unanswered]) == :neutral
    end

    test "qualquer questão marcada para depois deixa a página amarela", ctx do
      # mesmo com outras sem resposta, uma única marca já basta
      assert Attempts.page_status([ctx.later, ctx.unanswered, ctx.answered]) == :yellow
      assert Attempts.page_status([ctx.later, ctx.answered], true) == :yellow
    end

    test "página completa fica verde", ctx do
      assert Attempts.page_status([ctx.answered, ctx.dont_know]) == :green
      # respondida ainda marcada para depois conta como completa
      assert Attempts.page_status([ctx.answered_later, ctx.answered]) == :green
      assert Attempts.page_status([]) == :green
    end

    test "vermelho só após a validação da confirmação", ctx do
      assert Attempts.page_status([ctx.unanswered, ctx.answered], true) == :red
      # vermelho tem prioridade sobre amarelo depois de validado
      assert Attempts.page_status([ctx.unanswered, ctx.later], true) == :red
    end
  end
end
