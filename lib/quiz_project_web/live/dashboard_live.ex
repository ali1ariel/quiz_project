defmodule QuizProjectWeb.DashboardLive do
  use QuizProjectWeb, :live_view

  alias QuizProject.Attempts
  alias QuizProject.Quizzes

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
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
        <p :if={@created == []} class="opacity-60 text-sm py-8 text-center">
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
                :if={published_version(quiz) && version_suffix(published_version(quiz).version_number)}
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
            <p :if={published_version(quiz)} class="text-xs opacity-60 mt-1 truncate">
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

      <div :if={@tab == :answered} id="answered-list" class="space-y-3">
        <p :if={@answered == []} class="opacity-60 text-sm py-8 text-center">
          Você ainda não respondeu nenhum quiz.
        </p>

        <div
          :for={attempt <- @answered}
          id={"attempt-#{attempt.id}"}
          class="card qcard bg-base-200 p-4 flex flex-col sm:flex-row sm:items-center gap-3"
        >
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-semibold truncate">{attempt.quiz_version.name}</span>
              <span
                :if={version_suffix(attempt.quiz_version.version_number)}
                class="badge badge-sm badge-ghost rounded-full"
              >
                {version_suffix(attempt.quiz_version.version_number)}
              </span>
              <span
                :if={attempt.status == :finished}
                class="badge badge-sm badge-success rounded-full"
              >
                {format_decimal(attempt.score)}/{format_decimal(attempt.max_score)} pts
              </span>
              <span
                :if={attempt.status == :in_progress}
                class="badge badge-sm badge-warning rounded-full"
              >
                em andamento
              </span>
            </div>
            <p class="text-xs opacity-60 mt-1">
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
              :if={attempt.status == :in_progress}
              navigate={~p"/tentativa/#{attempt.id}"}
              class="btn btn-sm btn-primary rounded-full"
            >
              Continuar
            </.link>
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
          <p class="text-sm opacity-70 mb-3">
            Envie um arquivo .json ou cole o conteúdo abaixo. O quiz importado
            entra como rascunho para revisão antes da publicação.
          </p>

          <a
            href={~p"/template.json"}
            download="template-quiz.json"
            class="btn btn-sm btn-outline rounded-full mb-4"
            id="download-template"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Baixar template.json
          </a>
          <p class="text-xs opacity-60 mb-4 -mt-2">
            Baixe o modelo e envie para a IA de sua preferência gerar o quiz no formato aceito.
          </p>

          <div :if={@import_errors != []} class="alert alert-error rounded-xl mb-3 text-sm">
            <ul class="list-disc list-inside">
              <li :for={error <- @import_errors}>{error}</li>
            </ul>
          </div>

          <form phx-change="validate_import" phx-submit="import_quiz" id="import-form">
            <div
              class="border-2 border-dashed border-base-300 rounded-xl p-4 mb-3 text-center"
              phx-drop-target={@uploads.json_file.ref}
            >
              <.live_file_input
                upload={@uploads.json_file}
                class="file-input file-input-bordered file-input-sm w-full max-w-xs rounded-full"
              />
              <p class="text-xs opacity-60 mt-2">Arquivo .json (máx. 1 MB)</p>
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

            <div class="divider text-xs opacity-60 my-2">ou cole o JSON</div>

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
                Importar como rascunho
              </button>
            </div>
          </form>
        </div>
      </dialog>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(tab: :created, show_import: false, import_errors: [], import_json: "")
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
      answered: Attempts.list_answered(user)
    )
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
    {:noreply, assign(socket, show_import: true, import_errors: [], import_json: "")}
  end

  def handle_event("close_import", _params, socket) do
    {:noreply, assign(socket, show_import: false)}
  end

  def handle_event("validate_import", params, socket) do
    {:noreply, assign(socket, import_json: params["json"] || socket.assigns.import_json)}
  end

  def handle_event("import_quiz", params, socket) do
    # arquivo enviado tem prioridade sobre o texto colado
    json =
      case consume_uploaded_entries(socket, :json_file, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end) do
        [content | _] -> content
        [] -> params["json"] || ""
      end

    case Quizzes.import_quiz(socket.assigns.current_user, json) do
      {:ok, version} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quiz importado como rascunho. Revise antes de publicar.")
         |> push_navigate(to: ~p"/quiz/#{version.id}/editar")}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, import_errors: errors, import_json: json)}

      {:error, _} ->
        {:noreply,
         assign(socket, import_errors: ["Erro inesperado na importação"], import_json: json)}
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
