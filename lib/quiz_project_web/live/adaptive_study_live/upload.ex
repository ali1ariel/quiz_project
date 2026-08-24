defmodule QuizProjectWeb.AdaptiveStudyLive.Upload do
  use QuizProjectWeb, :live_view

  alias QuizProject.AdaptiveStudy

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(
       page_title: "Novo Conteúdo - Estudo Adaptativo",
       loading?: false,
       title: "",
       raw_content: "",
       ai_authorized?: QuizProject.AI.Authorization.authorized?(to_string(user.email))
     )
     |> allow_upload(:content_file, accept: ~w(.txt .md .pdf), max_entries: 1)}
  end

  @impl true
  def handle_event("validate", %{"title" => title, "raw_content" => raw_content}, socket) do
    {:noreply, assign(socket, title: title, raw_content: raw_content)}
  end

  @impl true
  def handle_event("save", params, socket) do
    title = Map.get(params, "title", "") |> String.trim()
    raw_content_param = Map.get(params, "raw_content", "") |> String.trim()

    uploaded_content =
      consume_uploaded_entries(socket, :content_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)
      |> Enum.join("\n\n")
      |> String.trim()

    final_content =
      cond do
        uploaded_content != "" -> uploaded_content
        raw_content_param != "" -> raw_content_param
        true -> ""
      end

    cond do
      # O botão já vem desabilitado para quem não está autorizado — isto é a
      # garantia do lado do servidor, para o evento que chega direto pelo
      # socket não processar mesmo assim.
      not socket.assigns.ai_authorized? ->
        {:noreply,
         put_flash(socket, :error, "Seu usuário não está autorizado a processar com IA.")}

      final_content == "" ->
        {:noreply,
         put_flash(socket, :error, "Insira um texto ou faça upload de um arquivo para continuar.")}

      true ->
        user = socket.assigns.current_user

        case AdaptiveStudy.create_material(user, %{
               title: if(title != "", do: title, else: "Processando material..."),
               raw_content: final_content,
               status: "draft"
             }) do
          {:ok, material} ->
            # Processa com IA em background via Jobs.run para evitar timeouts
            AdaptiveStudy.process_material_async(material, user)

            {:noreply,
             socket
             |> put_flash(
               :info,
               "Seu conteúdo está sendo processado em segundo plano pela IA. Você receberá uma notificação assim que o Mapa Mental estiver pronto!"
             )
             |> push_navigate(to: ~p"/study")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Não foi possível salvar o material.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      loose_captures_count={@loose_captures_count}
      active_nav={:adaptive_study}
    >
      <div class="space-y-6">
        <div class="flex items-center justify-between border-b border-base-300 pb-4">
          <div>
            <.link
              navigate={~p"/study"}
              class="text-xs font-semibold text-primary hover:underline flex items-center gap-1"
            >
              <.icon name="hero-arrow-left" class="size-3" /> Voltar aos materiais
            </.link>
            <h1 class="text-2xl font-bold tracking-tight mt-1">Novo Material de Estudo</h1>
            <p class="text-sm opacity-70">
              Cole o texto de estudo ou envie um arquivo (`.txt`, `.md`, `.pdf`). A IA fará a decomposição atômica em Mapa Mental. Para ler um livro inteiro, use Conteúdos.
            </p>
          </div>
        </div>

        <form id="upload-study-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <div class="space-y-2">
            <label for="material-title" class="block text-sm font-semibold">
              Título do Material
              <span class="text-xs font-normal opacity-60">(opcional - a IA gerará um se em branco)</span>
            </label>
            <input
              type="text"
              id="material-title"
              name="title"
              value={@title}
              placeholder="Ex: Arquitetura Elixir e OTP"
              class="input input-bordered w-full rounded-2xl"
              disabled={@loading?}
            />
          </div>

          <div class="space-y-2">
            <label class="block text-sm font-semibold">Upload de Arquivo (.txt, .md, .pdf)</label>
            <div class="rounded-2xl border-2 border-dashed border-base-300 p-6 text-center bg-base-200/50 hover:bg-base-200 transition">
              <.live_file_input
                upload={@uploads.content_file}
                class="file-input file-input-bordered w-full max-w-xs"
              />
              <p class="text-xs opacity-60 mt-2">
                Formatos suportados: Arquivos de texto, Markdown ou PDF de estudo.
              </p>

              <div
                :for={entry <- @uploads.content_file.entries}
                class="mt-3 text-xs font-semibold text-primary flex items-center justify-center gap-2"
              >
                <.icon name="hero-document-text" class="size-4" /> {entry.client_name} ({(entry.client_size /
                                                                                            1024)
                |> Float.round(1)} KB)
              </div>
            </div>
          </div>

          <div class="divider text-xs opacity-50 uppercase tracking-widest">
            OU COLE O TEXTO ABAIXO
          </div>

          <div class="space-y-2">
            <label for="material-raw-content" class="block text-sm font-semibold">
              Conteúdo Bruto / Texto de Estudo
            </label>
            <textarea
              id="material-raw-content"
              name="raw_content"
              rows="12"
              placeholder="Cole o artigo, capítulo de livro, transcrição de aula ou notas de estudo aqui..."
              class="textarea textarea-bordered w-full rounded-2xl font-mono text-sm leading-relaxed"
              disabled={@loading?}
            >{@raw_content}</textarea>
          </div>

          <p :if={not @ai_authorized?} class="text-sm text-error">
            Seu usuário não está autorizado a processar conteúdo com IA.
          </p>

          <%!-- Empilhado no telefone, com a ação principal em cima: lado a lado
               os dois botões somam ~320px e estouram a tela de 320px.
               `flex-col-reverse` mantém a ordem de tabulação com Cancelar antes
               de enviar, sem deixá-lo por cima do botão principal. --%>
          <div class="flex flex-col-reverse gap-3 border-t border-base-200 pt-4 sm:flex-row sm:justify-end">
            <.link
              navigate={~p"/study"}
              class="btn btn-ghost rounded-full px-6 max-sm:w-full"
            >
              Cancelar
            </.link>
            <button
              type="submit"
              id="submit-generate-mindmap"
              class="btn btn-primary inline-flex items-center justify-center gap-2 rounded-full px-8 max-sm:w-full"
              disabled={@loading? or not @ai_authorized?}
              title={
                if @ai_authorized?, do: nil, else: "Seu usuário não está autorizado a processar com IA"
              }
            >
              <%= if @loading? do %>
                <.icon name="hero-arrow-path" class="size-5 motion-safe:animate-spin" />
                Processando com IA...
              <% else %>
                <.icon name="hero-sparkles" class="size-5" /> Gerar Mapa Mental
              <% end %>
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
