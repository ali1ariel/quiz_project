defmodule QuizProject.QuizzesTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Quizzes

  setup do
    {:ok, owner} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "outro@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{owner: owner, other: other}
  end

  defp draft_with_questions(owner) do
    {:ok, version} = Quizzes.create_draft_quiz(owner)

    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz de História"}, owner)

    {:ok, q1} =
      Quizzes.upsert_question(
        version,
        %{statement: "A Terra é plana?", type: :true_false, true_false_answer: false},
        [],
        owner
      )

    {:ok, q2} =
      Quizzes.upsert_question(
        version,
        %{statement: "Capital do Brasil?", type: :single},
        [
          %{text: "Brasília", correct: true, position: 0},
          %{text: "Rio de Janeiro", correct: false, position: 1}
        ],
        owner
      )

    {version, q1, q2}
  end

  describe "rascunho" do
    test "cria quiz com versão 1 em rascunho", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)

      assert version.status == :draft
      assert version.version_number == 1
      assert version.quiz.owner_id == owner.id
      assert Decimal.equal?(version.total_points, Decimal.new(100))
    end

    test "autosave atualiza dados básicos", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)

      {:ok, updated} =
        Quizzes.update_draft(
          version,
          %{name: "Meu quiz", description: "desc", unequal_weights: true},
          owner
        )

      assert updated.name == "Meu quiz"
      assert updated.unequal_weights
    end

    test "outro usuário não pode editar", %{owner: owner, other: other} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)

      assert {:error, :unauthorized} = Quizzes.update_draft(version, %{name: "hack"}, other)
      assert {:error, :unauthorized} = Quizzes.update_draft(version, %{name: "anon"}, nil)
    end

    test "upsert de questão preserva identidade das alternativas", %{owner: owner} do
      {version, _q1, q2} = draft_with_questions(owner)

      [opt_a, opt_b] = Enum.sort_by(q2.options, & &1.position)

      {:ok, updated} =
        Quizzes.upsert_question(
          version,
          %{id: q2.id, statement: "Qual é a capital do Brasil?"},
          [
            %{id: opt_a.id, text: "Brasília (DF)", correct: true, position: 0},
            %{text: "São Paulo", correct: false, position: 1}
          ],
          owner
        )

      updated_a = Enum.find(updated.options, &(&1.id == opt_a.id))
      assert updated_a.identity_key == opt_a.identity_key
      assert updated_a.text == "Brasília (DF)"

      # opt_b foi removida, uma nova criada
      refute Enum.any?(updated.options, &(&1.id == opt_b.id))
      assert length(updated.options) == 2
    end

    test "deletar questão reordena posições", %{owner: owner} do
      {_version, q1, q2} = draft_with_questions(owner)

      assert :ok = Quizzes.delete_question(q1, owner)

      remaining = Quizzes.get_question!(q2.id)
      assert remaining.position == 0
    end

    test "deletar rascunho único apaga o quiz", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)

      assert {:ok, :quiz_deleted} = Quizzes.delete_draft(version, owner)
      assert Quizzes.list_created(owner) == []
    end
  end

  describe "publicação" do
    test "valida antes de publicar", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)

      assert {:error, errors} = Quizzes.publish(version, owner)
      assert Enum.any?(errors, &(&1 =~ "nome"))
      assert Enum.any?(errors, &(&1 =~ "pelo menos uma questão"))
    end

    test "valida questão single sem correta", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)
      {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz"}, owner)

      {:ok, _} =
        Quizzes.upsert_question(
          version,
          %{statement: "Escolha", type: :single},
          [%{text: "A", correct: false, position: 0}, %{text: "B", correct: false, position: 1}],
          owner
        )

      assert {:error, errors} = Quizzes.publish(version, owner)
      assert Enum.any?(errors, &(&1 =~ "exatamente 1 alternativa"))
    end

    test "publica, congela e gera tags e hash", %{owner: owner} do
      {version, _, _} = draft_with_questions(owner)

      assert {:ok, published} = Quizzes.publish(version, owner)
      assert published.status == :published
      assert published.published_at
      assert published.changelog == ["Primeira versão publicada"]

      full = Quizzes.get_version_full!(published.id)

      for question <- full.questions do
        assert is_binary(question.compatibility_hash)
        assert is_list(question.ai_tags)
      end

      # publicada não pode mais ser editada
      assert {:error, _} = Quizzes.update_draft(published, %{name: "outro"}, owner)
    end
  end

  describe "versionamento" do
    test "ensure_draft copia a última publicada mantendo identidades", %{owner: owner} do
      {version, _, _} = draft_with_questions(owner)
      {:ok, published} = Quizzes.publish(version, owner)

      quiz = Quizzes.get_quiz!(published.quiz_id)
      {:ok, draft} = Quizzes.ensure_draft(quiz, owner)

      assert draft.status == :draft
      assert draft.version_number == 2

      published_full = Quizzes.get_version_full!(published.id)
      draft_keys = MapSet.new(draft.questions, & &1.identity_key)
      published_keys = MapSet.new(published_full.questions, & &1.identity_key)
      assert MapSet.equal?(draft_keys, published_keys)

      # chamada repetida retorna o mesmo rascunho
      {:ok, same} = Quizzes.ensure_draft(quiz, owner)
      assert same.id == draft.id
    end

    test "mudança de enunciado gera changelog e quebra compatibilidade", %{owner: owner} do
      {version, _, _} = draft_with_questions(owner)
      {:ok, published} = Quizzes.publish(version, owner)

      quiz = Quizzes.get_quiz!(published.quiz_id)
      {:ok, draft} = Quizzes.ensure_draft(quiz, owner)

      question = Enum.find(draft.questions, &(&1.type == :true_false))

      {:ok, _} =
        Quizzes.upsert_question(
          draft,
          %{id: question.id, statement: "A Terra é redonda?", true_false_answer: true},
          [],
          owner
        )

      {:ok, v2} = Quizzes.publish(Quizzes.get_version!(draft.id), owner)

      assert Enum.any?(v2.changelog, &(&1 =~ "Enunciado da questão"))

      v1_question =
        Quizzes.get_version_full!(published.id).questions
        |> Enum.find(&(&1.identity_key == question.identity_key))

      v2_question =
        Quizzes.get_version_full!(v2.id).questions
        |> Enum.find(&(&1.identity_key == question.identity_key))

      refute v1_question.compatibility_hash == v2_question.compatibility_hash
    end

    test "mudança apenas de peso mantém compatibilidade", %{owner: owner} do
      {version, q1, _} = draft_with_questions(owner)
      {:ok, _} = Quizzes.update_draft(version, %{unequal_weights: true}, owner)
      {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), owner)

      quiz = Quizzes.get_quiz!(published.quiz_id)
      {:ok, draft} = Quizzes.ensure_draft(quiz, owner)

      draft_q = Enum.find(draft.questions, &(&1.identity_key == q1.identity_key))

      {:ok, _} =
        Quizzes.upsert_question(
          draft,
          %{id: draft_q.id, weight: Decimal.new(30)},
          [],
          owner
        )

      {:ok, v2} = Quizzes.publish(Quizzes.get_version!(draft.id), owner)

      assert Enum.any?(v2.changelog, &(&1 =~ "Peso da questão"))

      v1_question =
        Quizzes.get_version_full!(published.id).questions
        |> Enum.find(&(&1.identity_key == q1.identity_key))

      v2_question =
        Quizzes.get_version_full!(v2.id).questions
        |> Enum.find(&(&1.identity_key == q1.identity_key))

      assert v1_question.compatibility_hash == v2_question.compatibility_hash
    end
  end

  describe "anulação" do
    test "anula questão publicada com motivo e changelog", %{owner: owner} do
      {version, _, _} = draft_with_questions(owner)
      {:ok, published} = Quizzes.publish(version, owner)

      question = hd(Quizzes.get_version_full!(published.id).questions)

      {:ok, annulled} = Quizzes.annul_question(question, "Enunciado ambíguo", owner)

      assert annulled.annulled
      assert annulled.annulled_reason == "Enunciado ambíguo"

      version_after = Quizzes.get_version!(published.id)
      assert Enum.any?(version_after.changelog, &(&1 =~ "anulada"))
    end

    test "não anula questão de rascunho", %{owner: owner} do
      {_version, q1, _} = draft_with_questions(owner)

      assert {:error, :not_published} = Quizzes.annul_question(q1, "motivo", owner)
    end
  end

  describe "importação JSON" do
    test "importa quiz válido como rascunho", %{owner: owner} do
      json = """
      {
        "nome": "Quiz importado",
        "descricao": "Veio de fora",
        "nota_total": 50,
        "pesos_desiguais": true,
        "modo_ordem": "aleatoria",
        "questoes": [
          {
            "enunciado": "2 + 2 = 4?",
            "tipo": "verdadeiro_falso",
            "resposta_verdadeiro_falso": true,
            "peso": 10
          },
          {
            "enunciado": "Selecione os pares",
            "tipo": "multipla",
            "nota_parcial": true,
            "alternativas": [
              {"texto": "2", "correta": true},
              {"texto": "3", "correta": false},
              {"texto": "4", "correta": true}
            ]
          },
          {
            "enunciado": "Explique a fotossíntese",
            "tipo": "discursiva",
            "resposta_referencia": "Processo de conversão de luz em energia química"
          }
        ]
      }
      """

      {:ok, version} = Quizzes.import_quiz(owner, json)

      assert version.status == :draft
      assert version.name == "Quiz importado"
      assert version.question_order_mode == :random
      assert version.unequal_weights
      assert length(version.questions) == 3

      multiple = Enum.find(version.questions, &(&1.type == :multiple))
      assert multiple.allow_partial_credit
      assert length(multiple.options) == 3
    end

    test "rejeita JSON com erros estruturais", %{owner: owner} do
      json = ~s({"nome": "", "questoes": [{"tipo": "unica", "alternativas": []}]})

      assert {:error, errors} = Quizzes.import_quiz(owner, json)
      assert Enum.any?(errors, &(&1 =~ "nome"))
      assert Enum.any?(errors, &(&1 =~ "enunciado"))
      assert Enum.any?(errors, &(&1 =~ "alternativas"))
    end

    test "rejeita JSON malformado", %{owner: owner} do
      assert {:error, [error]} = Quizzes.import_quiz(owner, "{nope")
      assert error =~ "JSON inválido"
    end
  end

  describe "link público" do
    test "resolve slug para a última versão publicada", %{owner: owner} do
      {version, _, _} = draft_with_questions(owner)
      {:ok, published} = Quizzes.publish(version, owner)

      quiz = Quizzes.get_quiz!(published.quiz_id)

      assert {:ok, {found_quiz, found_version}} = Quizzes.get_public_by_slug(quiz.public_slug)
      assert found_quiz.id == quiz.id
      assert found_version.id == published.id
    end

    test "quiz sem versão publicada não resolve", %{owner: owner} do
      {:ok, version} = Quizzes.create_draft_quiz(owner)
      quiz = Quizzes.get_quiz!(version.quiz_id)

      assert {:error, :not_found} = Quizzes.get_public_by_slug(quiz.public_slug)
      assert {:error, :not_found} = Quizzes.get_public_by_slug("inexistente")
    end
  end
end
