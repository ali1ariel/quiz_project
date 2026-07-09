defmodule QuizProjectWeb.DashboardLive do
  use QuizProjectWeb, :live_view

  import QuizProjectWeb.EvolutionChart

  alias QuizProject.Attempts
  alias QuizProject.Quizzes

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      notifications={@notifications}
      active_nav={:quizzes}
      wide
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-2xl font-bold">Meus quizzes</h1>
        <div class="flex gap-2">
          <button id="create-quiz" phx-click="create_quiz" class="btn btn-primary rounded-full">
            <.icon name="hero-plus" class="size-4" /> Criar quiz
          </button>
          <button
            id="open-import"
            phx-click="open_import"
            class="btn btn-outline rounded-full"
          >
            <.icon name="hero-arrow-up-tray" class="size-4" /> Importar quiz
          </button>
        </div>
      </div>

      <div role="tablist" class="tabs tabs-border">
        <button
          role="tab"
          id="tab-created"
          class={["tab", @tab == :created && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="created"
        >
          Quizzes criados
        </button>
        <button
          role="tab"
          id="tab-answered"
          class={["tab", @tab == :answered && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="answered"
        >
          Quizzes respondidos
        </button>
      </div>

      <div :if={@tab == :created} id="created-list" class="space-y-3">
        <p :if={@created == []} class="opacity-70 text-sm py-8 text-center">
          Você ainda não criou nenhum quiz. Clique em "Criar quiz" para começar.
        </p>

        <div
          :for={quiz <- @created}
          id={"quiz-#{quiz.id}"}
          class="card qcard bg-base-200 p-4 flex flex-col sm:flex-row sm:items-center gap-3"
        >
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-semibold truncate">{display_name(quiz)}</span>
              <span
                :if={published_version(quiz)}
                class="badge badge-success badge-sm rounded-full"
              >
                publicado
              </span>
              <span
                :if={
                  published_version(quiz) && version_suffix(published_version(quiz).version_number)
                }
                class="badge badge-ghost badge-sm rounded-full"
              >
                {version_suffix(published_version(quiz).version_number)}
              </span>
              <span
                :if={published_version(quiz) && !quiz.active}
                class="badge badge-neutral badge-sm rounded-full"
              >
                desativado
              </span>
              <span :if={draft_version(quiz)} class="badge badge-warning badge-sm rounded-full">
                rascunho
              </span>
            </div>
            <p :if={published_version(quiz)} class="text-xs opacity-70 mt-1 truncate">
              Link público: {url(~p"/q/#{quiz.public_slug}")}
            </p>
          </div>

          <div class="flex gap-2 flex-wrap">
            <button
              id={"edit-quiz-#{quiz.id}"}
              phx-click="edit_quiz"
              phx-value-quiz-id={quiz.id}
              class="btn btn-sm btn-outline rounded-full"
            >
              Editar
            </button>
            <.link
              :if={published_version(quiz)}
              id={"manage-quiz-#{quiz.id}"}
              navigate={~p"/quiz/#{quiz.id}/gerenciar"}
              class="btn btn-sm btn-outline rounded-full"
            >
              Respostas e versões
            </.link>
            <button
              :if={published_version(quiz)}
              id={"toggle-active-#{quiz.id}"}
              phx-click="toggle_active"
              phx-value-quiz-id={quiz.id}
              data-confirm={
                quiz.active && "Desativar o quiz? Ninguém poderá enviar novas respostas até reativar."
              }
              class="btn btn-sm btn-ghost rounded-full"
            >
              {if quiz.active, do: "Desativar", else: "Reativar"}
            </button>
            <.link
              :if={published_version(quiz) && quiz.active}
              href={~p"/q/#{quiz.public_slug}"}
              target="_blank"
              rel="noopener"
              class="btn btn-sm btn-ghost rounded-full"
            >
              Abrir link
            </.link>
          </div>
        </div>
      </div>

      <div :if={@tab == :answered} id="answered-list" class="space-y-4">
        <p :if={@answered_groups == []} class="opacity-70 text-sm py-8 text-center">
          Você ainda não respondeu nenhum quiz.
        </p>

        <div
          :for={group <- @answered_groups}
          id={"answered-quiz-#{group.quiz_id}"}
          class="card qcard bg-base-200 p-4 space-y-3"
        >
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-semibold truncate">{group.name}</span>
            <span class="badge badge-sm badge-ghost rounded-full">
              {group.count} {if group.count == 1, do: "tentativa", else: "tentativas"}
            </span>
            <.link
              :if={group.has_stats}
              id={"quiz-stats-#{group.quiz_id}"}
              navigate={~p"/quiz/#{group.quiz_id}/evolucao"}
              class="btn btn-xs btn-outline rounded-full ml-auto"
            >
              <.icon name="hero-chart-bar" class="size-3" /> Ver estatísticas
            </.link>
          </div>

          <div
            :for={version_group <- group.by_version}
            id={"answered-quiz-#{group.quiz_id}-v#{version_group.number}"}
            class="space-y-2"
          >
            <div class="flex items-center gap-2">
              <span class="badge badge-sm badge-neutral rounded-full">
                versão {version_group.number}
              </span>
              <span class="text-xs opacity-70">
                {length(version_group.attempts)} {if length(version_group.attempts) == 1,
                  do: "tentativa",
                  else: "tentativas"}
              </span>
            </div>

            <.evolution_chart
              :if={version_group.chart}
              chart={version_group.chart}
              id={"evolution-#{group.quiz_id}-v#{version_group.number}"}
            />

            <div
              :for={attempt <- version_group.attempts}
              id={"attempt-#{attempt.id}"}
              class="flex flex-col sm:flex-row sm:items-center gap-2 rounded-xl border border-base-300 px-3 py-2"
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span
                    :if={attempt.status == :finished}
                    class="badge badge-sm badge-success rounded-full"
                  >
                    {format_decimal(attempt.score)}/{format_decimal(attempt.max_score)} pts
                  </span>
                  <span
                    :if={attempt.status == :finished && attempt.percent}
                    class="text-sm font-semibold"
                  >
                    {format_decimal(attempt.percent)}%
                  </span>
                  <span
                    :if={attempt.status == :in_progress}
                    class="badge badge-sm badge-warning rounded-full"
                  >
                    em andamento
                  </span>
                  <span
                    :if={attempt.status == :processing}
                    class="badge badge-sm badge-info rounded-full inline-flex items-center gap-1"
                  >
                    <span class="loading loading-spinner loading-xs"></span> corrigindo…
                  </span>
                  <span :if={attempt_date(attempt)} class="text-xs opacity-70">
                    em {attempt_date(attempt)}
                  </span>
                </div>
                <p class="text-xs opacity-70 mt-0.5">
                  Identificado como "{attempt.display_identity}"
                </p>
              </div>

              <div class="flex gap-2">
                <.link
                  :if={attempt.status == :finished}
                  navigate={~p"/tentativa/#{attempt.id}/resultado"}
                  class="btn btn-sm btn-outline rounded-full"
                >
                  Ver resultado
                </.link>
                <.link
                  :if={attempt.status == :processing}
                  navigate={~p"/tentativa/#{attempt.id}/resultado"}
                  class="btn btn-sm btn-outline rounded-full"
                >
                  Acompanhar correção
                </.link>
                <.link
                  :if={attempt.status == :in_progress}
                  navigate={~p"/tentativa/#{attempt.id}"}
                  class="btn btn-sm btn-primary rounded-full"
                >
                  Continuar
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <dialog
        :if={@show_import}
        id="import-modal"
        class="modal modal-open"
        phx-window-keydown="close_import"
        phx-key="escape"
      >
        <div class="modal-box rounded-2xl max-w-2xl">
          <h3 class="font-bold text-lg mb-2">Importar quiz via JSON</h3>
          <div :if={@import_preview} id="import-preview" class="space-y-3">
            <p class="text-sm opacity-70">
              Confira o que foi reconhecido antes de importar. O quiz entra como
              rascunho para revisão antes da publicação.
            </p>

            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-semibold">
                {if @import_preview.attrs.name == "",
                  do: "Quiz sem nome",
                  else: @import_preview.attrs.name}
              </span>
              <span class="badge badge-sm badge-ghost rounded-full">
                {length(@import_preview.attrs.questions)} questões
              </span>
              <span class="badge badge-sm badge-ghost rounded-full">
                nota {format_decimal(@import_preview.attrs.total_points)}
              </span>
            </div>
            <p
              :if={@import_preview.attrs.description not in [nil, ""]}
              class="text-sm opacity-70"
            >
              {@import_preview.attrs.description}
            </p>

            <ul class="max-h-72 overflow-y-auto space-y-2 pr-1">
              <li
                :for={{question, index} <- Enum.with_index(@import_preview.attrs.questions)}
                class="text-sm border border-base-300 rounded-xl p-2"
              >
                <div class="flex items-start gap-2">
                  <span class="badge badge-neutral badge-sm rounded-full mt-0.5">{index + 1}</span>
                  <div class="min-w-0">
                    <p class="break-words">
                      {if question.statement == "", do: "(sem enunciado)", else: question.statement}
                    </p>
                    <p class="text-xs opacity-70 mt-0.5">
                      {type_label(question.type)} · {preview_detail(question)}
                    </p>
                  </div>
                </div>
              </li>
            </ul>

            <div class="modal-action">
              <button type="button" phx-click="cancel_preview" class="btn btn-ghost rounded-full">
                Voltar
              </button>
              <button
                type="button"
                phx-click="confirm_import"
                id="confirm-import"
                class="btn btn-primary rounded-full"
              >
                Confirmar importação
              </button>
            </div>
          </div>

          <div :if={!@import_preview}>
            <p class="text-sm opacity-70 mb-3">
              Envie um arquivo .json ou cole o conteúdo abaixo. O quiz importado
              entra como rascunho para revisão antes da publicação.
            </p>

            <a
              href={~p"/formato-importacao.md"}
              download="formato-importacao.md"
              class="btn btn-sm btn-outline rounded-full mb-4"
              id="download-format"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Baixar formato para IA
            </a>
            <p class="text-xs opacity-70 mb-4 -mt-2">
              Baixe a documentação do formato e envie para a IA de sua preferência: ela contém
              todas as regras e um exemplo para gerar o quiz já no formato aceito.
            </p>

            <div
              id="import-api-docs-hint"
              class="mb-4 flex items-start gap-3 rounded-xl border border-primary/25 bg-primary/5 p-3 text-xs leading-5"
            >
              <.icon name="hero-sparkles" class="mt-0.5 size-4 shrink-0 text-primary" />
              <p>
                Para importar direto pela IA, confira também nossa
                <.link
                  id="import-api-docs-link"
                  href={~p"/api/docs#usar-com-ia"}
                  target="_blank"
                  rel="noreferrer"
                  class="font-semibold text-primary underline decoration-primary/35 underline-offset-2 hover:decoration-primary"
                >
                  documentação da API
                </.link>
                e envie esse link para ela consultar antes de iniciar a importação.
              </p>
            </div>

            <div :if={@import_errors != []} class="alert alert-error rounded-xl mb-3 text-sm">
              <ul class="list-disc list-inside">
                <li :for={error <- @import_errors}>{error}</li>
              </ul>
            </div>

            <form phx-change="validate_import" phx-submit="preview_import" id="import-form">
              <div
                class="border-2 border-dashed border-base-300 rounded-xl p-4 mb-3 text-center"
                phx-drop-target={@uploads.json_file.ref}
              >
                <.live_file_input
                  upload={@uploads.json_file}
                  class="file-input file-input-bordered file-input-sm w-full max-w-xs rounded-full"
                />
                <p class="text-xs opacity-70 mt-2">Arquivo .json (máx. 1 MB)</p>
                <p
                  :for={entry <- @uploads.json_file.entries}
                  class="text-xs mt-1 font-mono"
                  id={"upload-entry-#{entry.ref}"}
                >
                  {entry.client_name}
                </p>
                <p
                  :for={error <- upload_errors(@uploads.json_file)}
                  class="text-xs text-error mt-1"
                >
                  {upload_error_message(error)}
                </p>
              </div>

              <div class="divider text-xs opacity-70 my-2">ou cole o JSON</div>

              <textarea
                name="json"
                id="import-json"
                rows="8"
                class="textarea textarea-bordered w-full rounded-xl font-mono text-xs"
                placeholder={import_placeholder()}
              >{@import_json}</textarea>
              <div class="modal-action">
                <button type="button" phx-click="close_import" class="btn btn-ghost rounded-full">
                  Cancelar
                </button>
                <button type="submit" id="import-submit" class="btn btn-primary rounded-full">
                  Revisar importação
                </button>
              </div>
            </form>
          </div>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       tab: :created,
       show_import: false,
       import_errors: [],
       import_json: "",
       import_preview: nil,
       page_title: build_title(["Meus quizzes"])
     )
     |> allow_upload(:json_file,
       accept: ~w(.json application/json),
       max_entries: 1,
       max_file_size: 1_000_000
     )
     |> load_lists()}
  end

  defp load_lists(socket) do
    user = socket.assigns.current_user

    assign(socket,
      created: Quizzes.list_created(user),
      answered_groups: group_answered(Attempts.list_answered(user))
    )
  end

  # Agrupa as tentativas por quiz (e, dentro do quiz, por versão), mantendo
  # os grupos ordenados pela tentativa mais recente. `list_answered` já vem
  # ordenado por inserted_at desc, então a primeira tentativa de cada grupo
  # é a mais recente. Versões não se misturam: cada versão tem sua própria
  # linha evolutiva, calculada só com as tentativas finalizadas dela.
  defp group_answered(attempts) do
    attempts
    |> Enum.group_by(& &1.quiz_version.quiz_id)
    |> Enum.map(fn {quiz_id, group} ->
      by_version =
        group
        |> Enum.group_by(& &1.quiz_version.version_number)
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.map(fn {number, version_attempts} ->
          %{
            number: number,
            attempts: version_attempts,
            chart: version_attempts |> finished_in_order() |> chart_data()
          }
        end)

      %{
        quiz_id: quiz_id,
        name: group_name(group),
        latest_at: hd(group).inserted_at,
        count: length(group),
        by_version: by_version,
        has_stats: Enum.any?(group, &(&1.status == :finished))
      }
    end)
    |> Enum.sort_by(& &1.latest_at, {:desc, DateTime})
  end

  defp group_name(group) do
    latest = Enum.max_by(group, & &1.quiz_version.version_number)

    case latest.quiz_version.name do
      name when name in [nil, ""] -> "Quiz sem nome"
      name -> name
    end
  end

  defp finished_in_order(group) do
    group
    |> Enum.filter(&(&1.status == :finished and &1.percent != nil and &1.finished_at != nil))
    |> Enum.sort_by(& &1.finished_at, DateTime)
  end

  defp attempt_date(attempt) do
    case attempt.finished_at || attempt.started_at do
      nil -> nil
      datetime -> Calendar.strftime(datetime, "%d/%m/%Y")
    end
  end

  # Correção em background terminou (broadcast do Notifier, assinado pelo
  # hook :notify_attempts): recarrega as listas ao vivo — a tentativa sai de
  # "corrigindo…" para a nota sem o usuário recarregar a página.
  def handle_info({:attempt_finished, _info}, socket) do
    {:noreply, load_lists(socket)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: String.to_existing_atom(tab))}
  end

  def handle_event("create_quiz", _params, socket) do
    {:ok, version} = Quizzes.create_draft_quiz(socket.assigns.current_user)
    {:noreply, push_navigate(socket, to: ~p"/quiz/#{version.id}/editar")}
  end

  def handle_event("toggle_active", %{"quiz-id" => quiz_id}, socket) do
    quiz = Quizzes.get_quiz!(quiz_id)

    case Quizzes.set_quiz_active(quiz, !quiz.active, socket.assigns.current_user) do
      {:ok, _} ->
        message =
          if quiz.active,
            do: "Quiz desativado. Novas respostas estão bloqueadas.",
            else: "Quiz reativado. Já aceita respostas."

        {:noreply, socket |> put_flash(:info, message) |> load_lists()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível alterar o status do quiz.")}
    end
  end

  def handle_event("edit_quiz", %{"quiz-id" => quiz_id}, socket) do
    quiz = Quizzes.get_quiz!(quiz_id)

    case Quizzes.ensure_draft(quiz, socket.assigns.current_user) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: ~p"/quiz/#{draft.id}/editar")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível abrir o quiz para edição.")}
    end
  end

  def handle_event("open_import", _params, socket) do
    {:noreply,
     assign(socket, show_import: true, import_errors: [], import_json: "", import_preview: nil)}
  end

  def handle_event("close_import", _params, socket) do
    {:noreply, assign(socket, show_import: false, import_preview: nil)}
  end

  def handle_event("validate_import", params, socket) do
    {:noreply, assign(socket, import_json: params["json"] || socket.assigns.import_json)}
  end

  def handle_event("preview_import", params, socket) do
    # arquivo enviado tem prioridade sobre o texto colado
    json =
      case consume_uploaded_entries(socket, :json_file, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end) do
        [content | _] -> content
        [] -> params["json"] || ""
      end

    case Quizzes.preview_import(json) do
      {:ok, attrs} ->
        {:noreply, assign(socket, import_preview: %{json: json, attrs: attrs}, import_errors: [])}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, import_errors: errors, import_json: json)}
    end
  rescue
    _ in [Jason.DecodeError, File.Error] ->
      {:noreply, assign(socket, import_errors: ["Erro ao ler o arquivo JSON"], import_json: nil)}
  end

  def handle_event("cancel_preview", _params, socket) do
    {:noreply, assign(socket, import_preview: nil)}
  end

  def handle_event("confirm_import", _params, socket) do
    case Quizzes.import_quiz(socket.assigns.current_user, socket.assigns.import_preview.json) do
      {:ok, version} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz importado como rascunho. Revise antes de publicar.")
         |> push_navigate(to: ~p"/quiz/#{version.id}/editar")}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, import_preview: nil, import_errors: errors)}

      {:error, _} ->
        {:noreply,
         assign(socket, import_preview: nil, import_errors: ["Erro inesperado na importação"])}
    end
  end

  defp display_name(quiz) do
    case quiz.versions do
      [latest | _] when latest.name not in [nil, ""] -> latest.name
      _ -> "Quiz sem nome"
    end
  end

  defp published_version(quiz), do: Enum.find(quiz.versions, &(&1.status == :published))
  defp draft_version(quiz), do: Enum.find(quiz.versions, &(&1.status == :draft))

  defp type_label(:true_false), do: "Verdadeiro ou falso"
  defp type_label(:single), do: "Uma correta"
  defp type_label(:multiple), do: "Múltiplas corretas"
  defp type_label(:text), do: "Discursiva"

  # Resumo da questão na pré-visualização da importação.
  defp preview_detail(%{type: :true_false, true_false_answer: answer}) do
    "resposta: " <> if(answer, do: "Verdadeiro", else: "Falso")
  end

  defp preview_detail(%{type: :single, options: options}) do
    "#{length(options)} alternativas · 1 correta"
  end

  defp preview_detail(%{type: :multiple, options: options} = question) do
    corretas = Enum.count(options, & &1.correct)
    parcial = if question.allow_partial_credit, do: " · nota parcial", else: ""
    "#{length(options)} alternativas · #{corretas} corretas#{parcial}"
  end

  defp preview_detail(%{type: :text, editor_note: note}) do
    if note in [nil, ""], do: "sem resposta de referência", else: "com resposta de referência"
  end

  defp format_decimal(nil), do: "0"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp upload_error_message(:too_large), do: "Arquivo grande demais (máx. 1 MB)"
  defp upload_error_message(:not_accepted), do: "Envie um arquivo .json"
  defp upload_error_message(:too_many_files), do: "Envie apenas um arquivo"
  defp upload_error_message(_), do: "Erro no upload do arquivo"

  defp import_placeholder do
    ~s({"nome": "Meu quiz", "questoes": [{"enunciado": "...", "tipo": "unica", "alternativas": [{"texto": "A", "correta": true}, {"texto": "B"}]}]})
  end
end
