defmodule QuizProject.PrioritiesTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.AdaptiveStudy
  alias QuizProject.Attempts
  alias QuizProject.Priorities
  alias QuizProject.Quizzes

  setup do
    {:ok, user} =
      Accounts.register_user(%{email: "dono@teste.com", password: "senha12345"},
        authorize?: false
      )

    {:ok, other} =
      Accounts.register_user(%{email: "outra@teste.com", password: "senha12345"},
        authorize?: false
      )

    %{user: user, other: other}
  end

  defp category(user, name \\ "Categoria") do
    {:ok, category} = Priorities.create_category(user, %{name: name})
    category
  end

  defp book(user) do
    {:ok, book} =
      AdaptiveStudy.create_material(user, %{title: "Livro", format: :epub, status: "draft"})

    book
  end

  defp manual_item(user, category, title) do
    {:ok, item} = Priorities.create_item(user, category, %{item_type: :manual, title: title})
    item
  end

  # Hábito é sempre extensão de uma prioridade — atalho pra testes que não
  # se importam com qual prioridade, só que exista uma.
  defp habit_item(user), do: manual_item(user, category(user), "Prioridade")

  # `item_type: :habit` não existe mais na constraint de `Item` — nem a
  # action `create` nem `Ash.Seed.seed!` aceitam construir um assim (o
  # `one_of` é validado na estrutura, não só na action). O único jeito de
  # simular uma linha legada de antes da Fase 4 (`Habit` virar resource
  # próprio) é inserir direto via SQL, ignorando a camada Ash por completo —
  # exatamente como uma linha desse tipo sobreviveria de verdade em produção.
  defp legacy_habit_item(user, category, title \\ "Legado") do
    id = Ecto.UUID.generate()

    Ecto.Adapters.SQL.query!(
      QuizProject.Repo,
      """
      INSERT INTO priority_items
        (id, user_id, category_id, item_type, title, position, general,
         manual_percent, manual_progress_mode, course_completed_steps, manual_completed_steps,
         inserted_at, updated_at)
      VALUES ($1, $2, $3, 'habit', $4, 0, false, 0, 'percent', 0, 0, now(), now())
      """,
      [
        Ecto.UUID.dump!(id),
        Ecto.UUID.dump!(user.id),
        Ecto.UUID.dump!(category.id),
        title
      ]
    )

    id
  end

  defp item_row_count(id) do
    import Ecto.Query

    QuizProject.Repo.aggregate(
      from(i in "priority_items", where: i.id == type(^id, :binary_id)),
      :count
    )
  end

  # Quiz publicado com uma questão V/F, resposta correta = verdadeiro.
  defp published_tf_quiz(owner) do
    {:ok, version} = Quizzes.create_draft_quiz(owner)
    {:ok, version} = Quizzes.update_draft(version, %{name: "Quiz simples"}, owner)

    {:ok, _} =
      Quizzes.upsert_question(
        version,
        %{statement: "Verdadeiro?", type: :true_false, true_false_answer: true},
        [],
        owner
      )

    {:ok, published} = Quizzes.publish(Quizzes.get_version!(version.id), owner)
    Quizzes.get_version_full!(published.id)
  end

  defp finished_attempt(version, user, percent_100?) do
    {:ok, attempt} = Attempts.start_attempt(version, %{user: user, token: "tok-#{user.id}"}, "P")

    if percent_100? do
      question = hd(attempt.quiz_version.questions)
      answer = Enum.find(attempt.answers, &(&1.question_id == question.id))
      {:ok, _} = Attempts.save_answer(attempt, answer, question, %{"value" => true})
    end

    {:ok, finished} = Attempts.finalize(attempt, force: true)
    finished
  end

  describe "categorias" do
    test "cria categorias em posições crescentes", %{user: user} do
      c1 = category(user, "Livros")
      c2 = category(user, "Hábitos")

      assert c1.position == 0
      assert c2.position == 1
      assert Enum.map(Priorities.list_categories(user), & &1.name) == ["Livros", "Hábitos"]
    end
  end

  describe "item \"Geral\" da categoria" do
    test "toda categoria nasce com um item Geral oculto", %{user: user} do
      cat = category(user, "Livros")

      geral = Priorities.general_item_for_category(cat)

      assert geral.category_id == cat.id
      assert geral.general == true
      assert geral.title == "Livros - Geral"
    end

    test "general_item_for_category é idempotente", %{user: user} do
      cat = category(user)

      a = Priorities.general_item_for_category(cat)
      b = Priorities.general_item_for_category(cat)

      assert a.id == b.id
    end

    test "cria o item Geral sob demanda pra categoria que ainda não tinha um", %{user: user} do
      cat = category(user)
      geral = Priorities.general_item_for_category(cat)
      {:ok, _} = Priorities.delete_item(geral, user)

      recriado = Priorities.general_item_for_category(cat)

      assert recriado.id != geral.id
      assert recriado.general == true
    end

    test "nunca aparece nas listagens normais de item", %{user: user} do
      cat = category(user, "Livros")
      geral = Priorities.general_item_for_category(cat)
      _visivel = manual_item(user, cat, "Item normal")

      refute geral.id in Enum.map(Priorities.list_items_by_category(cat.id), & &1.id)
      refute geral.id in Enum.map(Priorities.list_primary_items(cat.id), & &1.id)
      refute geral.id in Enum.map(Priorities.list_untiered_items(user), & &1.id)
      refute geral.id in Enum.map(Priorities.filter_items(user), & &1.id)
    end
  end

  describe "criação de itens por tipo" do
    test "cria um item de cada tipo com sucesso", %{user: user} do
      cat = category(user)
      livro = book(user)
      quiz = published_tf_quiz(user)

      assert {:ok, %{item_type: :book}} =
               Priorities.create_item(user, cat, %{
                 item_type: :book,
                 title: "Livro",
                 study_material_id: livro.id
               })

      assert {:ok, %{item_type: :quiz_goal}} =
               Priorities.create_item(user, cat, %{
                 item_type: :quiz_goal,
                 title: "Quiz",
                 quiz_id: quiz.quiz_id
               })

      assert {:ok, %{item_type: :course}} =
               Priorities.create_item(user, cat, %{
                 item_type: :course,
                 title: "Curso",
                 course_total_steps: 10
               })

      assert {:ok, %{item_type: :checklist}} =
               Priorities.create_item(user, cat, %{item_type: :checklist, title: "Checklist"})

      assert {:ok, %{item_type: :manual}} =
               Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})
    end

    test "recusa :book sem study_material_id", %{user: user} do
      cat = category(user)

      assert {:error, %Ash.Error.Invalid{}} =
               Priorities.create_item(user, cat, %{item_type: :book, title: "Livro"})
    end

    test "recusa :quiz_goal sem quiz_id", %{user: user} do
      cat = category(user)

      assert {:error, %Ash.Error.Invalid{}} =
               Priorities.create_item(user, cat, %{item_type: :quiz_goal, title: "Meta"})
    end

    test "aceita :course sem course_total_steps (etapas são opcionais)", %{user: user} do
      cat = category(user)

      assert {:ok, %{item_type: :course, course_total_steps: nil}} =
               Priorities.create_item(user, cat, %{item_type: :course, title: "Curso"})
    end

    test "recusa livro de outro usuário", %{user: user, other: other} do
      cat = category(user)
      livro_alheio = book(other)

      assert {:error, _} =
               Priorities.create_item(user, cat, %{
                 item_type: :book,
                 title: "Livro",
                 study_material_id: livro_alheio.id
               })
    end

    test "livro sem título usa o título do livro", %{user: user} do
      cat = category(user)

      {:ok, livro} =
        AdaptiveStudy.create_material(user, %{
          title: "Clean Code",
          format: :epub,
          status: "draft"
        })

      assert {:ok, item} =
               Priorities.create_item(user, cat, %{
                 item_type: :book,
                 title: "",
                 study_material_id: livro.id
               })

      assert item.title == "Clean Code"
    end

    test "livro com título explícito mantém o título escolhido", %{user: user} do
      cat = category(user)
      livro = book(user)

      assert {:ok, item} =
               Priorities.create_item(user, cat, %{
                 item_type: :book,
                 title: "Meu apelido pro livro",
                 study_material_id: livro.id
               })

      assert item.title == "Meu apelido pro livro"
    end

    test "aceita meta de quiz de um quiz que não é do usuário (quem responde não precisa ser o dono)",
         %{user: user, other: owner} do
      cat = category(user)
      quiz = published_tf_quiz(owner)

      assert {:ok, %{item_type: :quiz_goal}} =
               Priorities.create_item(user, cat, %{
                 item_type: :quiz_goal,
                 title: "Quiz de outra pessoa",
                 quiz_id: quiz.quiz_id
               })
    end

    test "item novo não altera posição/progresso de itens já existentes", %{user: user} do
      cat = category(user)

      {:ok, primeiro} =
        Priorities.create_item(user, cat, %{item_type: :manual, title: "Primeiro"})

      {:ok, primeiro} = Priorities.set_manual_percent(primeiro, 42, user)

      {:ok, _segundo} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Segundo"})

      recarregado = Enum.find(Priorities.list_items_by_category(cat.id), &(&1.id == primeiro.id))
      assert recarregado.position == primeiro.position
      assert recarregado.manual_percent == 42
    end
  end

  describe "arquivamento" do
    test "arquivar remove da listagem sem afetar os demais itens", %{user: user} do
      cat = category(user)
      {:ok, a} = Priorities.create_item(user, cat, %{item_type: :manual, title: "A"})
      {:ok, a} = Priorities.set_manual_percent(a, 10, user)
      {:ok, b} = Priorities.create_item(user, cat, %{item_type: :manual, title: "B"})
      {:ok, b} = Priorities.set_manual_percent(b, 20, user)

      {:ok, _} = Priorities.archive_item(a, user)

      ativos = Priorities.list_items_by_category(cat.id)
      assert Enum.map(ativos, & &1.id) == [b.id]

      recarregado_b = Enum.find(ativos, &(&1.id == b.id))
      assert recarregado_b.manual_percent == 20
    end
  end

  describe "delete_item/2" do
    test "dono exclui definitivamente", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Descartável"})

      assert {:ok, _} = Priorities.delete_item(item, user)
      assert {:error, _} = Priorities.get_item(item.id, user)
    end

    test "recusa exclusão por quem não é dono", %{user: user, other: other} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Descartável"})

      assert {:error, :unauthorized} = Priorities.delete_item(item, other)
      assert {:ok, _} = Priorities.get_item(item.id, user)
    end

    test "exclui subtarefas e tags junto (sem deixar órfãos)", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :checklist, title: "Lista"})
      {:ok, _task} = Priorities.create_task(item, "Fazer algo", user)
      {:ok, tag} = Priorities.find_or_create_tag(user, "urgente")
      {:ok, _} = Priorities.add_tag_to_item(item, tag, user)

      assert {:ok, _} = Priorities.delete_item(item, user)
      assert Priorities.list_tasks(item.id) == []
    end
  end

  describe "método de acesso do curso" do
    test "set_course_access/3 grava link, login e senha", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :course, title: "Curso"})

      attrs = %{
        course_access_link: "https://curso.exemplo.com",
        course_access_login: "aluno@exemplo.com",
        course_access_password: "s3nha"
      }

      assert {:ok, atualizado} = Priorities.set_course_access(item, attrs, user)
      assert atualizado.course_access_link == "https://curso.exemplo.com"
      assert atualizado.course_access_login == "aluno@exemplo.com"
      assert atualizado.course_access_password == "s3nha"
    end

    test "create_item aceita os campos de acesso direto na criação", %{user: user} do
      cat = category(user)

      assert {:ok, item} =
               Priorities.create_item(user, cat, %{
                 item_type: :course,
                 title: "Curso",
                 course_access_link: "https://curso.exemplo.com"
               })

      assert item.course_access_link == "https://curso.exemplo.com"
    end
  end

  describe "change_item_type/3" do
    test "troca o tipo mantendo o registro", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})

      assert {:ok, atualizado} =
               Priorities.change_item_type(
                 item,
                 %{item_type: :course, course_total_steps: 5},
                 user
               )

      assert atualizado.item_type == :course
      assert atualizado.course_total_steps == 5
      assert atualizado.id == item.id
    end

    test "recusa livro de outro usuário ao trocar para :book", %{user: user, other: other} do
      cat = category(user)
      livro_alheio = book(other)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})

      assert {:error, _} =
               Priorities.change_item_type(
                 item,
                 %{item_type: :book, study_material_id: livro_alheio.id},
                 user
               )
    end
  end

  describe "progress_for_item/1" do
    test ":book bate com AdaptiveStudy.Books.library_progress/2", %{user: user} do
      cat = category(user)
      livro = book(user)

      {:ok, item} =
        Priorities.create_item(user, cat, %{
          item_type: :book,
          title: "Livro",
          study_material_id: livro.id
        })

      assert Priorities.progress_for_item(item) == {:percent, nil}
    end

    test ":quiz_goal bate com Attempts.best_percent_for_quiz/2", %{user: user} do
      cat = category(user)
      quiz = published_tf_quiz(user)

      finished_attempt(quiz, user, false)
      finished_attempt(quiz, user, true)

      {:ok, item} =
        Priorities.create_item(user, cat, %{
          item_type: :quiz_goal,
          title: "Meta",
          quiz_id: quiz.quiz_id
        })

      assert Attempts.best_percent_for_quiz(user, quiz.quiz_id) |> Decimal.equal?(100)
      assert Priorities.progress_for_item(item) == {:percent, 100}
    end

    test ":course calcula percentual por etapas", %{user: user} do
      cat = category(user)

      {:ok, item} =
        Priorities.create_item(user, cat, %{
          item_type: :course,
          title: "Curso",
          course_total_steps: 4,
          course_completed_steps: 1
        })

      assert Priorities.progress_for_item(item) == {:percent, 25}
    end

    test ":checklist calcula percentual pelas subtarefas", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :checklist, title: "Lista"})

      {:ok, t1} = Priorities.create_task(item, "Passo 1", user)
      {:ok, _t2} = Priorities.create_task(item, "Passo 2", user)

      {:ok, _} = Priorities.toggle_task(t1, item, user)

      assert Priorities.progress_for_item(item) == {:percent, 50}
    end

    test ":manual devolve o percentual gravado", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})
      {:ok, item} = Priorities.set_manual_percent(item, 73, user)

      assert Priorities.progress_for_item(item) == {:percent, 73}
    end

    test ":manual em modo etapas calcula o percentual", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})

      {:ok, item} =
        Priorities.set_manual_steps(
          item,
          %{manual_completed_steps: 3, manual_total_steps: 4},
          user
        )

      assert Priorities.progress_for_item(item) == {:percent, 75}
    end

    test ":manual volta pro modo percentual ao gravar um percentual direto", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Manual"})

      {:ok, item} =
        Priorities.set_manual_steps(
          item,
          %{manual_completed_steps: 1, manual_total_steps: 2},
          user
        )

      {:ok, item} = Priorities.set_manual_percent(item, 10, user)

      assert Priorities.progress_for_item(item) == {:percent, 10}
    end
  end

  describe "hábitos" do
    test "cria hábito :daily por padrão, sempre extensão de uma prioridade", %{user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Academia")

      {:ok, habit} = Priorities.create_habit(user, %{title: "Hábito", item_id: item.id})
      assert habit.frequency == :daily
      assert habit.item_id == item.id

      assert {:error, _} = Priorities.create_habit(user, %{title: "Sem prioridade"})
    end

    test "rejeita item de outro usuário", %{user: user, other: other} do
      item = manual_item(other, category(other), "Alheio")

      assert {:error, :unauthorized} =
               Priorities.create_habit(user, %{title: "Hábito", item_id: item.id})
    end

    test "set_habit_frequency muda pra semanal e persiste", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      {:ok, _} =
        Priorities.set_habit_frequency(habit, %{frequency: :weekly, weekdays: [1, 3, 5]}, user)

      {:ok, atualizado} = Priorities.get_habit(habit.id, user)
      assert atualizado.frequency == :weekly
      assert atualizado.weekdays == [1, 3, 5]
    end

    test "ensure_today_habit_instance cria a instância de hoje quando devido, sem duplicar", %{
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      :ok = Priorities.ensure_today_habit_instance(habit, user)
      :ok = Priorities.ensure_today_habit_instance(habit, user)

      activities =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      assert [%{logical_date: date, status: :pendente}] = activities
      assert date == Date.utc_today()
    end

    test "não cria instância quando o dia não é devido (semanal fora do dia)", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      hoje_semana = Date.day_of_week(Date.utc_today())
      outro_dia = if hoje_semana == 1, do: 2, else: 1

      {:ok, habit} =
        Priorities.set_habit_frequency(habit, %{frequency: :weekly, weekdays: [outro_dia]}, user)

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      assert Priorities.list_today_activities(user)
             |> Enum.filter(&(&1.habit_id == habit.id)) == []
    end

    test "instância vencida ainda pendente vira não cumprida ao garantir a de hoje", %{
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      {:ok, vencida} =
        Priorities.create_activity(user, %{
          title: "Hábito",
          habit_id: habit.id,
          logical_date: Date.add(Date.utc_today(), -1)
        })

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      {:ok, atualizada} = Priorities.get_activity(vencida.id, user)
      assert atualizada.status == :nao_cumprida
    end

    test "dia devido em que o app não foi aberto vira não cumprido (backfill), sem travar o de hoje",
         %{user: user} do
      hoje = Date.utc_today()
      tres_dias_atras = Date.add(hoje, -3)

      {:ok, habit} =
        Priorities.create_habit(user, %{
          title: "Academia",
          item_id: habit_item(user).id,
          starts_on: tres_dias_atras
        })

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      instances =
        Priorities.list_activities_between(user, tres_dias_atras, hoje)
        |> Enum.filter(&(&1.habit_id == habit.id))
        |> Map.new(&{&1.logical_date, &1.status})

      assert instances == %{
               tres_dias_atras => :nao_cumprida,
               Date.add(hoje, -2) => :nao_cumprida,
               Date.add(hoje, -1) => :nao_cumprida,
               hoje => :pendente
             }
    end

    test "habit_streak conta dias devidos consecutivos concluídos", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      hoje = Date.utc_today()
      ontem = Date.add(hoje, -1)
      anteontem = Date.add(hoje, -2)

      for date <- [hoje, ontem, anteontem] do
        {:ok, activity} =
          Priorities.create_activity(user, %{title: "H", habit_id: habit.id, logical_date: date})

        {:ok, _} = Priorities.complete_activity(activity, user)
      end

      assert Priorities.habit_streak(habit.id) == 3
    end

    test "habit_streak quebra num dia devido sem instância concluída", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      hoje = Date.utc_today()

      {:ok, activity} =
        Priorities.create_activity(user, %{title: "H", habit_id: habit.id, logical_date: hoje})

      {:ok, _} = Priorities.complete_activity(activity, user)

      # ontem não tem nenhuma atividade — quebra a sequência antes de contar
      assert Priorities.habit_streak(habit.id) == 1
    end

    test "atividade não pode estar presa a item e a hábito ao mesmo tempo", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Item"})

      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Hábito", item_id: habit_item(user).id})

      assert {:error, _} =
               Priorities.create_activity(user, %{
                 title: "Inválida",
                 item_id: item.id,
                 habit_id: habit.id
               })
    end
  end

  describe "itens legados item_type: :habit (self-healing)" do
    test "list_items_by_category remove o item legado e apaga a linha", %{user: user} do
      cat = category(user)
      manual_item(user, cat, "Fica")
      legacy_id = legacy_habit_item(user, cat)

      titles = Priorities.list_items_by_category(cat.id) |> Enum.map(& &1.title)
      assert titles == ["Fica"]
      assert item_row_count(legacy_id) == 0
    end

    test "get_item retorna not_found pro item legado e apaga a linha", %{user: user} do
      cat = category(user)
      legacy_id = legacy_habit_item(user, cat)

      assert {:error, :not_found} = Priorities.get_item(legacy_id, user)
      assert item_row_count(legacy_id) == 0
    end

    test "list_untiered_items e list_tiered_items também removem o item legado", %{user: user} do
      cat = category(user)
      legacy_habit_item(user, cat, "Legado sem tier")

      assert Priorities.list_untiered_items(user) == []
      assert Priorities.list_tiered_items(user) |> Enum.flat_map(&elem(&1, 1)) == []
    end

    test "filter_items também remove o item legado", %{user: user} do
      cat = category(user)
      legacy_habit_item(user, cat, "Legado filtro")

      assert Priorities.filter_items(user) == []
    end
  end

  describe "upcoming_habit_schedule/2" do
    test "diário aparece todo dia, semanal só no dia certo, arquivado nunca aparece", %{
      user: user
    } do
      item = habit_item(user)

      {:ok, _diario} = Priorities.create_habit(user, %{title: "Diário", item_id: item.id})
      {:ok, arquivado} = Priorities.create_habit(user, %{title: "Arquivado", item_id: item.id})
      {:ok, _} = Priorities.archive_habit(arquivado, user)

      tomorrow = Date.add(Date.utc_today(), 1)
      tomorrow_weekday = Date.day_of_week(tomorrow)

      {:ok, _semanal} =
        Priorities.create_habit(user, %{
          title: "Semanal",
          item_id: item.id,
          frequency: :weekly,
          weekdays: [tomorrow_weekday]
        })

      schedule = Priorities.upcoming_habit_schedule(user, 7)

      assert length(schedule) == 7
      assert Enum.all?(schedule, &(&1.date != Date.utc_today()))
      assert Enum.at(schedule, 0).date == tomorrow

      titles_tomorrow = Enum.at(schedule, 0).habits |> Enum.map(& &1.title) |> Enum.sort()
      assert titles_tomorrow == Enum.sort(["Diário", "Semanal"])

      other_day =
        Enum.find(
          schedule,
          &(&1.date != tomorrow and Date.day_of_week(&1.date) != tomorrow_weekday)
        )

      titles_other_day = Enum.map(other_day.habits, & &1.title)
      assert "Diário" in titles_other_day
      refute "Semanal" in titles_other_day

      assert Enum.all?(schedule, fn day -> Enum.all?(day.habits, &(&1.title != "Arquivado")) end)
    end
  end

  describe "exceção de hábito por data (HabitOverride)" do
    test "sem exceção, habit_due_on?/2 e occurrence_title/2 seguem a regra normal", %{
      user: user
    } do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      amanha = Date.add(Date.utc_today(), 1)

      assert Priorities.habit_due_on?(habit, amanha)
      assert Priorities.occurrence_title(habit, amanha) == "Meditar"
    end

    test "pular um dia tira ele de habit_due_on?/2 sem afetar outros dias", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      amanha = Date.add(Date.utc_today(), 1)
      depois = Date.add(amanha, 1)

      {:ok, _} = Priorities.set_habit_occurrence_override(habit, amanha, %{skipped: true}, user)

      refute Priorities.habit_due_on?(habit, amanha)
      assert Priorities.habit_due_on?(habit, depois)
    end

    test "título de exceção só vale pra aquele dia", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      amanha = Date.add(Date.utc_today(), 1)
      depois = Date.add(amanha, 1)

      {:ok, _} =
        Priorities.set_habit_occurrence_override(
          habit,
          amanha,
          %{title: "Academia - perna"},
          user
        )

      assert Priorities.occurrence_title(habit, amanha) == "Academia - perna"
      assert Priorities.occurrence_title(habit, depois) == "Academia"
    end

    test "salvar exceção pra mesma data de novo atualiza em vez de duplicar", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      amanha = Date.add(Date.utc_today(), 1)

      {:ok, _} = Priorities.set_habit_occurrence_override(habit, amanha, %{skipped: true}, user)
      {:ok, _} = Priorities.set_habit_occurrence_override(habit, amanha, %{skipped: false}, user)

      refute Priorities.get_habit_occurrence_override(habit.id, amanha).skipped
    end

    test "clear_habit_occurrence_override remove a exceção e é idempotente", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      amanha = Date.add(Date.utc_today(), 1)

      {:ok, _} = Priorities.set_habit_occurrence_override(habit, amanha, %{skipped: true}, user)
      :ok = Priorities.clear_habit_occurrence_override(habit, amanha, user)

      assert Priorities.get_habit_occurrence_override(habit.id, amanha) == nil
      assert Priorities.habit_due_on?(habit, amanha)

      # chamar de novo sem exceção nenhuma não deve dar erro
      assert :ok = Priorities.clear_habit_occurrence_override(habit, amanha, user)
    end

    test "ensure_today_habit_instance não cria atividade quando hoje está pulado", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Meditar", item_id: habit_item(user).id})

      hoje = Date.utc_today()

      {:ok, _} = Priorities.set_habit_occurrence_override(habit, hoje, %{skipped: true}, user)
      :ok = Priorities.ensure_today_habit_instance(habit, user)

      assert Priorities.list_today_activities(user)
             |> Enum.filter(&(&1.habit_id == habit.id)) == []
    end

    test "ensure_today_habit_instance usa o título de exceção de hoje", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      hoje = Date.utc_today()

      {:ok, _} =
        Priorities.set_habit_occurrence_override(habit, hoje, %{title: "Academia - perna"}, user)

      :ok = Priorities.ensure_today_habit_instance(habit, user)

      [activity] =
        Priorities.list_today_activities(user) |> Enum.filter(&(&1.habit_id == habit.id))

      assert activity.title == "Academia - perna"
    end
  end

  describe "change_habit_frequency_from/4" do
    test "encerra o hábito atual no dia anterior e cria um novo a partir da data, com a regra nova",
         %{user: user} do
      cat = category(user)
      item = manual_item(user, cat, "Academia")

      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: item.id})

      data_corte = Date.add(Date.utc_today(), 3)

      {:ok, novo} =
        Priorities.change_habit_frequency_from(
          habit,
          data_corte,
          %{frequency: :weekly, weekdays: [1, 3, 5]},
          user
        )

      {:ok, antigo_atualizado} = Priorities.get_habit(habit.id, user)
      assert antigo_atualizado.ends_on == Date.add(data_corte, -1)
      # a regra do hábito antigo não muda, só o limite
      assert antigo_atualizado.frequency == :daily

      assert novo.starts_on == data_corte
      assert novo.frequency == :weekly
      assert novo.weekdays == [1, 3, 5]
      assert novo.title == "Academia"
      assert novo.item_id == item.id
      assert novo.id != habit.id
    end

    test "dias antes da data de corte continuam com a regra antiga na prévia", %{user: user} do
      {:ok, habit} =
        Priorities.create_habit(user, %{title: "Academia", item_id: habit_item(user).id})

      data_corte = Date.add(Date.utc_today(), 3)

      {:ok, _novo} =
        Priorities.change_habit_frequency_from(
          habit,
          data_corte,
          %{frequency: :monthly, month_days: [1]},
          user
        )

      schedule = Priorities.upcoming_habit_schedule(user, 7)

      dia_antes = Enum.find(schedule, &(&1.date == Date.add(data_corte, -1)))
      titles_antes = Enum.map(dia_antes.habits, & &1.title)
      assert "Academia" in titles_antes
    end
  end

  describe "tags" do
    test "find_or_create_tag/2 não duplica", %{user: user} do
      {:ok, t1} = Priorities.find_or_create_tag(user, "urgente")
      {:ok, t2} = Priorities.find_or_create_tag(user, "urgente")

      assert t1.id == t2.id
      assert length(Priorities.list_tags(user)) == 1
    end

    test "associar e desassociar tag ao item", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Item"})
      {:ok, tag} = Priorities.find_or_create_tag(user, "importante")

      {:ok, item} = Priorities.add_tag_to_item(item, tag, user)
      item = Ash.load!(item, [:tags], authorize?: false)
      assert Enum.map(item.tags, & &1.id) == [tag.id]

      {:ok, item} = Priorities.remove_tag_from_item(item, tag, user)
      item = Ash.load!(item, [:tags], authorize?: false)
      assert item.tags == []
    end
  end

  describe "categorias secundárias" do
    test "item aparece na categoria primária e na secundária", %{user: user} do
      primaria = category(user, "Primária")
      secundaria = category(user, "Secundária")

      {:ok, item} =
        Priorities.create_item(user, primaria, %{item_type: :manual, title: "Item"})

      {:ok, _} = Priorities.add_secondary_category(item, secundaria, user)

      assert Enum.map(Priorities.list_items_by_category(primaria.id), & &1.id) == [item.id]
      assert Enum.map(Priorities.list_items_by_category(secundaria.id), & &1.id) == [item.id]
    end

    test "rejeita categoria secundária igual à primária", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Item"})

      assert {:error, :is_primary} = Priorities.add_secondary_category(item, cat, user)
    end
  end

  describe "campos customizados" do
    test "grava valor de texto, seleção e número no atributo certo", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Item"})

      {:ok, texto} =
        Priorities.create_field_definition(user, %{name: "Observação", field_type: :text})

      {:ok, selecao} =
        Priorities.create_field_definition(user, %{
          name: "Prioridade",
          field_type: :select,
          select_options: ["baixa", "alta"]
        })

      {:ok, numero} =
        Priorities.create_field_definition(user, %{name: "Nota", field_type: :number})

      {:ok, fv_texto} = Priorities.set_field_value(item, texto, "anotação livre", user)
      {:ok, fv_selecao} = Priorities.set_field_value(item, selecao, "alta", user)
      {:ok, fv_numero} = Priorities.set_field_value(item, numero, "9.5", user)

      assert fv_texto.value_text == "anotação livre"
      assert fv_selecao.value_text == "alta"
      assert fv_numero.value_number == 9.5
      assert fv_numero.value_text == nil
    end

    test "definir o mesmo campo de novo atualiza o valor (upsert)", %{user: user} do
      cat = category(user)
      {:ok, item} = Priorities.create_item(user, cat, %{item_type: :manual, title: "Item"})

      {:ok, campo} =
        Priorities.create_field_definition(user, %{name: "Nota", field_type: :number})

      {:ok, _} = Priorities.set_field_value(item, campo, "1", user)
      {:ok, atualizado} = Priorities.set_field_value(item, campo, "2", user)

      assert atualizado.value_number == 2.0

      item = Ash.load!(item, [:field_values], authorize?: false)
      assert length(item.field_values) == 1
    end
  end

  describe "list_tiered_items/1" do
    test "agrupa na ordem fixa S/A/B/C/D, com empate no mesmo tier", %{user: user} do
      cat = category(user)
      {:ok, a} = Priorities.create_item(user, cat, %{item_type: :manual, title: "A"})
      {:ok, b} = Priorities.create_item(user, cat, %{item_type: :manual, title: "B"})
      {:ok, _c} = Priorities.create_item(user, cat, %{item_type: :manual, title: "C sem tier"})

      {:ok, _} = Priorities.set_tier(a, :S, user)
      {:ok, _} = Priorities.set_tier(b, :S, user)

      tiers = Priorities.list_tiered_items(user)
      assert Enum.map(tiers, &elem(&1, 0)) == [:S, :A, :B, :C, :D]
      assert length(Keyword.get(tiers, :S)) == 2
      assert Keyword.get(tiers, :A) == []
    end
  end

  describe "filter_items/2" do
    test "combina filtro de categoria e tag", %{user: user} do
      cat1 = category(user, "Cat 1")
      cat2 = category(user, "Cat 2")

      {:ok, item1} = Priorities.create_item(user, cat1, %{item_type: :manual, title: "Item 1"})
      {:ok, _item2} = Priorities.create_item(user, cat2, %{item_type: :manual, title: "Item 2"})

      {:ok, tag} = Priorities.find_or_create_tag(user, "foco")
      {:ok, _} = Priorities.add_tag_to_item(item1, tag, user)

      resultado = Priorities.filter_items(user, category_id: cat1.id, tag_id: tag.id)
      assert Enum.map(resultado, & &1.id) == [item1.id]

      vazio = Priorities.filter_items(user, category_id: cat2.id, tag_id: tag.id)
      assert vazio == []
    end
  end

  describe "authorize_owner/2" do
    test "recusa ator que não é dono", %{user: user, other: other} do
      cat = category(user)
      assert {:error, :unauthorized} = Priorities.reposition_category(cat, 1, other)
    end
  end
end
