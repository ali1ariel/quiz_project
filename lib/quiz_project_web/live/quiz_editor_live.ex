defmodule QuizProjectWeb.QuizEditorLive do
  @moduledoc """
  Editor de rascunho de quiz: dados básicos com autosave, questões via modal,
  publicação e exclusão. Versões publicadas não abrem aqui — o painel cria um
  novo rascunho a partir da última publicada.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Quizzes

  @type_options [
    {"Verdadeiro ou falso", "true_false"},
    {"Marcar uma alternativa correta", "single"},
    {"Marcar múltiplas corretas", "multiple"},
    {"Resposta por texto (discursiva)", "text"}
  ]

  @order_options [
    {"Ordem definida", "fixed"},
    {"Ordem aleatória", "random"},
    {"Ordenação aleatória por IA", "ai"}
  ]

  @editor_note_placeholder "Explique a resposta esperada, o raciocínio correto ou os critérios " <>
                             "de avaliação. Este conteúdo será exibido no resultado e poderá ser " <>
                             "usado pela IA como referência para corrigir respostas discursivas."

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold">
            {if @version.version_number == 1, do: "Criar quiz", else: "Editar quiz"}
          </h1>
          <span class="badge badge-warning rounded-full">
            rascunho<span :if={version_suffix(@version.version_number)}>
              · {version_suffix(@version.version_number)}
            </span>
          </span>
          <span :if={@saved_at} class="text-xs opacity-50" id="autosave-indicator">
            salvo automaticamente
          </span>
        </div>

        <div class="flex flex-wrap justify-end gap-2">
          <button
            id="cancel-quiz"
            phx-click="delete_draft"
            data-confirm="Descartar este rascunho? As alterações não publicadas serão perdidas."
            class="btn btn-ghost text-error rounded-full"
          >
            Cancelar
          </button>
          <button
            :if={@has_published}
            id="toggle-active"
            phx-click="toggle_active"
            data-confirm={
              @quiz.active && "Desativar o quiz? Ninguém poderá enviar novas respostas até reativar."
            }
            class="btn btn-ghost rounded-full"
          >
            {if @quiz.active, do: "Desativar quiz", else: "Reativar quiz"}
          </button>
          <button
            id="save-quiz"
            phx-click="save"
            class="btn btn-outline rounded-full phx-click-loading:pointer-events-none phx-click-loading:opacity-70"
          >
            <span class="loading loading-spinner loading-xs hidden phx-click-loading:inline-block"></span>
            <span class="phx-click-loading:hidden">Salvar</span>
            <span class="hidden phx-click-loading:inline">Salvando…</span>
          </button>
          <button
            id="publish-quiz"
            phx-click="publish"
            class="btn btn-primary rounded-full phx-click-loading:pointer-events-none phx-click-loading:opacity-80"
          >
            <span class="loading loading-spinner loading-xs hidden phx-click-loading:inline-block"></span>
            <span class="phx-click-loading:hidden">Salvar e publicar</span>
            <span class="hidden phx-click-loading:inline">Publicando…</span>
          </button>
        </div>
      </div>

      <div
        :if={@publish_errors != []}
        class="alert alert-error rounded-2xl text-sm"
        id="publish-errors"
      >
        <div>
          <p class="font-semibold mb-1">Corrija antes de publicar:</p>
          <ul class="list-disc list-inside">
            <li :for={error <- @publish_errors}>{error}</li>
          </ul>
        </div>
      </div>

      <form phx-change="autosave" id="quiz-form" class="card qcard bg-base-200 p-5 space-y-4">
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <label class="label text-sm mb-1" for="quiz-name">Nome do quiz</label>
            <input
              type="text"
              name="name"
              id="quiz-name"
              value={@version.name}
              phx-debounce="400"
              class="input input-bordered w-full rounded-full"
              placeholder="Ex.: Prova de História — Brasil Império"
            />
          </div>
          <div>
            <label class="label text-sm mb-1" for="quiz-total-points">Nota total</label>
            <input
              type="number"
              name="total_points"
              id="quiz-total-points"
              value={format_decimal(@version.total_points)}
              min="1"
              step="any"
              phx-debounce="400"
              class="input input-bordered w-full rounded-full"
            />
          </div>
        </div>

        <div>
          <label class="label text-sm mb-1" for="quiz-description">Descrição</label>
          <textarea
            name="description"
            id="quiz-description"
            rows="2"
            phx-debounce="400"
            class="textarea textarea-bordered w-full rounded-xl"
            placeholder="Explique do que se trata o quiz"
          >{@version.description}</textarea>
        </div>

        <div class="grid sm:grid-cols-2 gap-4 items-end">
          <div>
            <label class="label text-sm mb-1" for="quiz-order-mode">Ordem das questões</label>
            <select
              name="question_order_mode"
              id="quiz-order-mode"
              class="select select-bordered w-full rounded-full"
            >
              <option
                :for={{label, value} <- order_options()}
                value={value}
                selected={to_string(@version.question_order_mode) == value}
              >
                {label}
              </option>
            </select>
            <p :if={@version.question_order_mode == :ai} class="text-xs opacity-60 mt-1">
              A IA gera tags internas na publicação e a ordem intercala temas — sem
              chamadas de IA durante a resposta.
            </p>
          </div>

          <label
            class="label cursor-pointer items-start justify-start gap-3 whitespace-normal pb-2"
            for="quiz-unequal-weights"
          >
            <input
              type="checkbox"
              name="unequal_weights"
              id="quiz-unequal-weights"
              class="toggle toggle-primary mt-0.5 shrink-0"
              checked={@version.unequal_weights}
            />
            <span class="label-text whitespace-normal">
              Permitir notas/pesos desiguais entre questões
            </span>
          </label>
        </div>
      </form>

      <div class="flex items-center justify-between mt-2">
        <h2 class="text-lg font-semibold">Perguntas ({length(@questions)})</h2>
        <button
          id="add-question"
          phx-click="new_question"
          class="btn btn-primary btn-circle"
          title="Adicionar pergunta"
        >
          <.icon name="hero-plus" class="size-5" />
        </button>
      </div>

      <p :if={@questions == []} class="opacity-60 text-sm py-6 text-center">
        Nenhuma pergunta ainda. Use o botão "+" para adicionar.
      </p>

      <div
        :for={{question, index} <- Enum.with_index(@questions)}
        id={"question-#{question.id}"}
        class="card qcard bg-base-200 p-4"
      >
        <div class="flex items-start gap-3">
          <span class="badge badge-neutral rounded-full mt-1">{index + 1}</span>
          <div class="flex-1 min-w-0">
            <p class="qtext font-medium break-words">
              {if question.statement == "", do: "(sem enunciado)", else: question.statement}
            </p>
            <div class="flex flex-wrap gap-2 mt-1 text-xs">
              <span class="badge badge-ghost badge-sm rounded-full">{type_label(question.type)}</span>
              <span :if={question.weight} class="badge badge-ghost badge-sm rounded-full">
                peso {format_decimal(question.weight)}
              </span>
              <span :if={question.annulled} class="badge badge-error badge-sm rounded-full">
                anulada
              </span>
              <span :if={question.type in [:single, :multiple]} class="opacity-60">
                {length(question.options)} alternativas
              </span>
            </div>
            <p :if={question.annulled && question.annulled_reason} class="text-xs opacity-60 mt-1">
              Motivo da anulação: {question.annulled_reason}
            </p>
          </div>
          <div class="flex gap-1">
            <button
              phx-click="move_question"
              phx-value-id={question.id}
              phx-value-direction="up"
              class="btn btn-ghost btn-xs btn-circle"
              disabled={index == 0}
              title="Mover para cima"
            >
              <.icon name="hero-chevron-up" class="size-4" />
            </button>
            <button
              phx-click="move_question"
              phx-value-id={question.id}
              phx-value-direction="down"
              class="btn btn-ghost btn-xs btn-circle"
              disabled={index == length(@questions) - 1}
              title="Mover para baixo"
            >
              <.icon name="hero-chevron-down" class="size-4" />
            </button>
            <button
              id={"edit-question-#{question.id}"}
              phx-click="edit_question"
              phx-value-id={question.id}
              class="btn btn-ghost btn-xs btn-circle"
              title="Editar"
            >
              <.icon name="hero-pencil" class="size-4" />
            </button>
            <button
              :if={!question.annulled}
              id={"annul-question-#{question.id}"}
              phx-click="open_annul"
              phx-value-id={question.id}
              class="btn btn-ghost btn-xs btn-circle text-warning"
              title="Anular questão"
            >
              <.icon name="hero-no-symbol" class="size-4" />
            </button>
            <button
              :if={question.annulled}
              id={"revert-annul-#{question.id}"}
              phx-click="revert_annul"
              phx-value-id={question.id}
              class="btn btn-ghost btn-xs btn-circle text-success"
              title="Reverter anulação"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" />
            </button>
          </div>
        </div>
      </div>

      <dialog :if={@question_form} id="question-modal" class="modal modal-open">
        <div class="modal-box rounded-2xl max-w-2xl">
          <h3 class="font-bold text-lg mb-4">
            {if @question_form["id"], do: "Editar pergunta", else: "Adicionar pergunta"}
          </h3>

          <form
            phx-change="question_change"
            phx-submit="save_question"
            id="question-form"
            class="space-y-4"
          >
            <div>
              <label class="label text-sm mb-1" for="question-statement">Enunciado</label>
              <textarea
                name="statement"
                id="question-statement"
                rows="3"
                class="textarea textarea-bordered w-full rounded-xl"
                placeholder="Escreva a pergunta"
              >{@question_form["statement"]}</textarea>
            </div>

            <div>
              <label class="label text-sm mb-1" for="question-type">Tipo da pergunta</label>
              <select
                name="type"
                id="question-type"
                class="select select-bordered w-full rounded-full"
              >
                <option
                  :for={{label, value} <- type_options()}
                  value={value}
                  selected={@question_form["type"] == value}
                >
                  {label}
                </option>
              </select>
            </div>

            <div :if={@question_form["type"] == "true_false"}>
              <span class="label text-sm mb-1">Resposta correta</span>
              <div class="flex gap-4">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="radio"
                    name="true_false_answer"
                    value="true"
                    class="radio radio-primary"
                    checked={@question_form["true_false_answer"] == "true"}
                  />
                  <span>Verdadeiro</span>
                </label>
                <label class="label cursor-pointer gap-2">
                  <input
                    type="radio"
                    name="true_false_answer"
                    value="false"
                    class="radio radio-primary"
                    checked={@question_form["true_false_answer"] == "false"}
                  />
                  <span>Falso</span>
                </label>
              </div>
            </div>

            <div :if={@question_form["type"] in ["single", "multiple"]}>
              <div class="flex items-center justify-between gap-2 mb-1">
                <span class="label whitespace-normal text-sm">
                  Alternativas — marque {if @question_form["type"] == "single",
                    do: "a correta",
                    else: "as corretas"}
                </span>
                <button
                  type="button"
                  id="add-option"
                  phx-click="add_option"
                  class="btn btn-ghost btn-xs rounded-full"
                >
                  <.icon name="hero-plus" class="size-3" /> alternativa
                </button>
              </div>

              <div :for={option <- @question_options} class="flex items-center gap-2 mb-2">
                <input
                  :if={@question_form["type"] == "single"}
                  type="radio"
                  name="correct_single"
                  value={option.key}
                  class="radio radio-success"
                  checked={option.correct}
                />
                <input
                  :if={@question_form["type"] == "multiple"}
                  type="checkbox"
                  name={"correct_multi[#{option.key}]"}
                  class="checkbox checkbox-success"
                  checked={option.correct}
                />
                <input
                  type="text"
                  name={"option_text[#{option.key}]"}
                  value={option.text}
                  placeholder="Texto da alternativa"
                  class="input input-bordered input-sm flex-1 rounded-full"
                />
                <button
                  type="button"
                  phx-click="remove_option"
                  phx-value-key={option.key}
                  class="btn btn-ghost btn-xs btn-circle text-error"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <label
                :if={@question_form["type"] == "multiple"}
                class="label cursor-pointer items-start justify-start gap-3 whitespace-normal mt-2"
              >
                <input
                  type="checkbox"
                  name="allow_partial_credit"
                  class="toggle toggle-sm toggle-primary mt-0.5 shrink-0"
                  checked={@question_form["allow_partial_credit"] == "true"}
                />
                <span class="label-text whitespace-normal text-sm">
                  Nota parcial: só corretas (sem todas) vale proporcional; qualquer incorreta zera
                </span>
              </label>
            </div>

            <div>
              <label class="label text-sm mb-1" for="question-editor-note">
                Resposta de referência (opcional)
              </label>
              <textarea
                name="editor_note"
                id="question-editor-note"
                rows="3"
                class="textarea textarea-bordered w-full rounded-xl"
                placeholder={editor_note_placeholder()}
              >{@question_form["editor_note"]}</textarea>
            </div>

            <div>
              <label class="label text-sm mb-1" for="question-weight">Peso da questão</label>
              <input
                type="number"
                name="weight"
                id="question-weight"
                value={@question_form["weight"]}
                min="0"
                step="any"
                disabled={not @version.unequal_weights}
                class="input input-bordered w-full rounded-full"
              />
              <p class="text-xs opacity-60 mt-1">
                {if @version.unequal_weights,
                  do:
                    "Se o peso não for preenchido, a nota será distribuída automaticamente entre as questões.",
                  else:
                    "Ative \"pesos desiguais\" nos dados do quiz para editar o peso. Sem pesos, a nota é distribuída igualmente."}
              </p>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="close_question" class="btn btn-ghost rounded-full">
                Cancelar
              </button>
              <button type="submit" id="save-question" class="btn btn-primary rounded-full">
                Salvar pergunta
              </button>
            </div>
          </form>
        </div>
      </dialog>

      <dialog :if={@annul_question} id="annul-modal" class="modal modal-open">
        <div class="modal-box rounded-2xl">
          <h3 class="font-bold text-lg mb-2">Anular questão</h3>
          <p class="text-sm opacity-70 mb-3">"{@annul_question.statement}"</p>
          <p class="text-sm mb-3">
            A questão fica marcada como anulada: permanece visível no resultado com selo de
            anulada e concede pontuação integral a todos, independentemente da resposta. Você
            pode reverter enquanto o rascunho não é publicado.
          </p>
          <form phx-submit="confirm_annul" id="annul-form">
            <textarea
              name="reason"
              id="annul-reason"
              rows="3"
              required
              class="textarea textarea-bordered w-full rounded-xl"
              placeholder="Explique o motivo da anulação (será exibido aos participantes)"
            ></textarea>
            <div class="modal-action">
              <button type="button" phx-click="close_annul" class="btn btn-ghost rounded-full">
                Cancelar
              </button>
              <button type="submit" id="confirm-annul" class="btn btn-warning rounded-full">
                Anular questão
              </button>
            </div>
          </form>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  def mount(%{"version_id" => version_id}, _session, socket) do
    version = Quizzes.get_version_full!(version_id)

    with :ok <- Quizzes.authorize_owner(version.quiz, socket.assigns.current_user),
         :draft <- version.status do
      {:ok,
       socket
       |> assign(
         version: version,
         quiz: version.quiz,
         has_published: not is_nil(Quizzes.latest_published_version(version.quiz)),
         questions: Enum.sort_by(version.questions, & &1.position),
         question_form: nil,
         question_options: [],
         annul_question: nil,
         publish_errors: [],
         saved_at: nil,
         page_title: editor_page_title(version)
       )}
    else
      :published ->
        {:ok, push_navigate(socket, to: ~p"/quiz/#{version.quiz_id}/gerenciar")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Você não tem acesso a esse quiz.")
         |> push_navigate(to: ~p"/painel")}
    end
  end

  ## Dados básicos (autosave)

  def handle_event("autosave", params, socket) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      total_points: parse_decimal(params["total_points"]) || socket.assigns.version.total_points,
      unequal_weights: params["unequal_weights"] == "on",
      question_order_mode: params["question_order_mode"]
    }

    case Quizzes.update_draft(socket.assigns.version, attrs, socket.assigns.current_user) do
      {:ok, version} ->
        {:noreply,
         assign(socket,
           version: version,
           saved_at: DateTime.utc_now(),
           page_title: editor_page_title(version)
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, put_flash(socket, :info, "Rascunho salvo.")}
  end

  def handle_event("publish", _params, socket) do
    case Quizzes.publish(socket.assigns.version, socket.assigns.current_user) do
      {:ok, published} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz publicado! Compartilhe o link público.")
         |> push_navigate(to: ~p"/quiz/#{published.quiz_id}/gerenciar")}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, publish_errors: errors)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível publicar.")}
    end
  end

  def handle_event("delete_draft", _params, socket) do
    case Quizzes.delete_draft(socket.assigns.version, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rascunho descartado.")
         |> push_navigate(to: ~p"/painel")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível descartar o rascunho.")}
    end
  end

  def handle_event("toggle_active", _params, socket) do
    quiz = socket.assigns.quiz

    case Quizzes.set_quiz_active(quiz, !quiz.active, socket.assigns.current_user) do
      {:ok, updated} ->
        message =
          if quiz.active,
            do: "Quiz desativado. Novas respostas estão bloqueadas.",
            else: "Quiz reativado. Já aceita respostas."

        {:noreply, socket |> assign(quiz: updated) |> put_flash(:info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível alterar o status do quiz.")}
    end
  end

  ## Anulação de questão

  def handle_event("open_annul", %{"id" => id}, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == id))
    {:noreply, assign(socket, annul_question: question)}
  end

  def handle_event("close_annul", _params, socket) do
    {:noreply, assign(socket, annul_question: nil)}
  end

  def handle_event("confirm_annul", %{"reason" => reason}, socket) do
    case Quizzes.set_question_annulment(
           socket.assigns.annul_question,
           true,
           reason,
           socket.assigns.current_user
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(annul_question: nil)
         |> reload_version()
         |> put_flash(:info, "Questão anulada. Todos recebem a pontuação integral.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível anular a questão.")}
    end
  end

  def handle_event("revert_annul", %{"id" => id}, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == id))

    case Quizzes.set_question_annulment(question, false, nil, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> reload_version() |> put_flash(:info, "Anulação revertida.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível reverter a anulação.")}
    end
  end

  ## Modal de pergunta

  def handle_event("new_question", _params, socket) do
    {:noreply,
     assign(socket,
       question_form: %{
         "id" => nil,
         "statement" => "",
         "type" => "single",
         "true_false_answer" => "true",
         "allow_partial_credit" => "false",
         "editor_note" => "",
         "weight" => ""
       },
       question_options: [new_option(), new_option()]
     )}
  end

  def handle_event("edit_question", %{"id" => id}, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == id))

    options =
      question.options
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn option ->
        %{key: option.id, id: option.id, text: option.text, correct: option.correct}
      end)

    {:noreply,
     assign(socket,
       question_form: %{
         "id" => question.id,
         "statement" => question.statement,
         "type" => to_string(question.type),
         "true_false_answer" => to_string(question.true_false_answer || true),
         "allow_partial_credit" => to_string(question.allow_partial_credit),
         "editor_note" => question.editor_note || "",
         "weight" => if(question.weight, do: format_decimal(question.weight), else: "")
       },
       question_options: if(options == [], do: [new_option(), new_option()], else: options)
     )}
  end

  def handle_event("close_question", _params, socket) do
    {:noreply, assign(socket, question_form: nil, question_options: [])}
  end

  def handle_event("question_change", params, socket) do
    {:noreply, apply_question_params(socket, params)}
  end

  def handle_event("add_option", _params, socket) do
    {:noreply,
     assign(socket, question_options: socket.assigns.question_options ++ [new_option()])}
  end

  def handle_event("remove_option", %{"key" => key}, socket) do
    {:noreply,
     assign(socket,
       question_options: Enum.reject(socket.assigns.question_options, &(&1.key == key))
     )}
  end

  def handle_event("save_question", params, socket) do
    socket = apply_question_params(socket, params)
    form = socket.assigns.question_form
    type = String.to_existing_atom(form["type"])

    question_attrs =
      %{
        id: form["id"],
        statement: String.trim(form["statement"]),
        type: type,
        true_false_answer: if(type == :true_false, do: form["true_false_answer"] == "true"),
        allow_partial_credit: type == :multiple and form["allow_partial_credit"] == "true",
        editor_note: presence(form["editor_note"]),
        weight: parse_decimal(form["weight"])
      }
      |> then(fn attrs -> if attrs.id, do: attrs, else: Map.delete(attrs, :id) end)

    options_attrs =
      if type in [:single, :multiple] do
        socket.assigns.question_options
        |> Enum.with_index()
        |> Enum.map(fn {option, index} ->
          %{id: option.id, text: option.text, correct: option.correct, position: index}
        end)
      else
        []
      end

    case Quizzes.upsert_question(
           socket.assigns.version,
           question_attrs,
           options_attrs,
           socket.assigns.current_user
         ) do
      {:ok, _question} ->
        {:noreply,
         socket
         |> assign(question_form: nil, question_options: [])
         |> reload_version()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar a pergunta.")}
    end
  end

  def handle_event("move_question", %{"id" => id, "direction" => direction}, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == id))

    Quizzes.move_question(
      question,
      String.to_existing_atom(direction),
      socket.assigns.current_user
    )

    {:noreply, reload_version(socket)}
  end

  ## Apoio

  defp apply_question_params(socket, params) do
    form =
      socket.assigns.question_form
      |> Map.merge(
        Map.take(params, [
          "statement",
          "type",
          "true_false_answer",
          "editor_note",
          "weight"
        ])
      )
      |> Map.put(
        "allow_partial_credit",
        to_string(Map.has_key?(params, "allow_partial_credit"))
      )

    options =
      socket.assigns.question_options
      |> Enum.map(fn option ->
        text = get_in(params, ["option_text", option.key]) || option.text

        correct =
          case form["type"] do
            "single" -> params["correct_single"] == option.key
            "multiple" -> get_in(params, ["correct_multi", option.key]) == "on"
            _ -> option.correct
          end

        %{option | text: text, correct: correct}
      end)

    # eventos que não vêm do form completo (add/remove) não trazem os checks
    options =
      if Map.has_key?(params, "option_text") or Map.has_key?(params, "correct_single") or
           Map.has_key?(params, "correct_multi") or Map.has_key?(params, "statement") do
        options
      else
        socket.assigns.question_options
      end

    assign(socket, question_form: form, question_options: options)
  end

  defp reload_version(socket) do
    version = Quizzes.get_version_full!(socket.assigns.version.id)

    assign(socket,
      version: version,
      questions: Enum.sort_by(version.questions, & &1.position)
    )
  end

  defp new_option do
    %{key: "new-" <> Ecto.UUID.generate(), id: nil, text: "", correct: false}
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(String.replace(value, ",", ".")) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp format_decimal(decimal) do
    decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp type_label(:true_false), do: "Verdadeiro ou falso"
  defp type_label(:single), do: "Uma correta"
  defp type_label(:multiple), do: "Múltiplas corretas"
  defp type_label(:text), do: "Discursiva"

  # v1 é criação (sem nome ainda no fluxo); demais versões são edição do quiz.
  defp editor_page_title(%{version_number: 1}), do: build_title(["Criando"])
  defp editor_page_title(version), do: build_title(["Editando", title_name(version.name)])

  defp type_options, do: @type_options
  defp order_options, do: @order_options
  defp editor_note_placeholder, do: @editor_note_placeholder
end
