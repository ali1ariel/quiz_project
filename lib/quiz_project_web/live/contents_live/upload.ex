defmodule QuizProjectWeb.ContentsLive.Upload do
  @moduledoc """
  Envio de um livro para a biblioteca.

  Só `.epub`: o formato declara a ordem de leitura no spine e numera os blocos,
  que é o que a leitura precisa. Texto solto continua entrando por Estudo
  Adaptativo, onde ele tem uso.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.Epub

  # Sem teto explícito o LiveView usa 8MB e rejeita o livro antes de qualquer
  # parser rodar — um técnico com imagens passa disso com folga.
  @max_file_size 80_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Adicionar livro", title: "")
     |> allow_upload(:book,
       accept: ~w(.epub),
       max_entries: 1,
       max_file_size: @max_file_size
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, title: Map.get(params, "title", ""))}
  end

  @impl true
  def handle_event("save", params, socket) do
    title = params |> Map.get("title", "") |> String.trim()

    case consume_uploaded_entries(socket, :book, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [binary | _] -> save_book(socket, title, binary)
      [] -> {:noreply, put_flash(socket, :error, "Escolha um arquivo .epub para continuar.")}
    end
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # DRM e layout fixo são condições do pacote, não do conteúdo: dá para
  # reconhecê-los sem extrair o livro, e a recusa sai aqui, na tela, em vez de
  # virar um livro quebrado que só se descobre depois.
  defp save_book(socket, title, binary) do
    user = socket.assigns.current_user

    with {:ok, info} <- Epub.inspect_package(binary),
         {:ok, book} <-
           AdaptiveStudy.create_material(user, %{
             title: if(title != "", do: title, else: info.title),
             author: info.author,
             format: :epub,
             status: "ingesting"
           }) do
      Books.ingest_async(book, binary, user)

      {:noreply,
       socket
       |> put_flash(
         :info,
         "\"#{book.title}\" está sendo lido: #{info.chapter_count} capítulos. A biblioteca avisa quando terminar."
       )
       |> push_navigate(to: ~p"/contents")}
    else
      {:error, reason} when is_atom(reason) ->
        {:noreply, put_flash(socket, :error, Epub.error_message(reason))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar o livro.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:contents}>
      <div class="mx-auto max-w-2xl space-y-6">
        <div class="border-b border-base-300 pb-4">
          <.link
            navigate={~p"/contents"}
            class="flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-3" /> Voltar à biblioteca
          </.link>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">Adicionar livro</h1>
          <p class="text-sm opacity-70">
            O arquivo é dividido em capítulos e blocos pela ordem de leitura que o próprio EPUB
            declara — sem IA em nenhuma etapa.
          </p>
        </div>

        <form id="upload-book-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <div class="space-y-2">
            <label for="book-title" class="block text-sm font-semibold">
              Título
              <span class="text-xs font-normal opacity-60">
                (opcional — em branco, usa o do próprio livro)
              </span>
            </label>
            <input
              type="text"
              id="book-title"
              name="title"
              value={@title}
              placeholder="Ex: Deep Learning with Python"
              class="input input-bordered w-full rounded-2xl"
            />
          </div>

          <div class="space-y-2">
            <label class="block text-sm font-semibold">Arquivo EPUB</label>
            <div
              class="rounded-2xl border-2 border-dashed border-base-300 bg-base-200/50 p-4 text-center transition hover:bg-base-200 sm:p-6"
              phx-drop-target={@uploads.book.ref}
            >
              <.live_file_input
                upload={@uploads.book}
                class="file-input file-input-bordered w-full sm:max-w-xs"
              />
              <p class="mt-2 text-xs opacity-60">
                Até 80 MB. EPUB 2 e 3. Livro com DRM ou de layout fixo não abre.
              </p>

              <div
                :for={entry <- @uploads.book.entries}
                class="mt-3 space-y-2 text-xs font-semibold text-primary"
              >
                <p class="flex items-center justify-center gap-2">
                  <.icon name="hero-book-open" class="size-4" />
                  {entry.client_name} ({Float.round(entry.client_size / 1_048_576, 1)} MB)
                </p>
                <div class="mx-auto h-1 max-w-xs overflow-hidden rounded-full bg-base-300">
                  <div class="h-full bg-primary transition-all" style={"width: #{entry.progress}%"}>
                  </div>
                </div>
                <p
                  :for={error <- upload_errors(@uploads.book, entry)}
                  class="font-normal text-error"
                >
                  {upload_error(error)}
                </p>
              </div>

              <p :for={error <- upload_errors(@uploads.book)} class="mt-2 text-xs text-error">
                {upload_error(error)}
              </p>
            </div>
          </div>

          <%!-- Empilhado no telefone, com a ação principal em cima, como no envio
               de material de estudo. --%>
          <div class="flex flex-col-reverse gap-3 border-t border-base-200 pt-4 sm:flex-row sm:justify-end">
            <.link navigate={~p"/contents"} class="btn btn-ghost rounded-full px-6 max-sm:w-full">
              Cancelar
            </.link>
            <button
              type="submit"
              id="submit-book"
              class="btn btn-primary inline-flex items-center justify-center gap-2 rounded-full px-8 max-sm:w-full"
            >
              <.icon name="hero-book-open" class="size-5" /> Adicionar à biblioteca
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: "O arquivo passa de 80 MB."
  defp upload_error(:not_accepted), do: "Só arquivos .epub são aceitos aqui."
  defp upload_error(:too_many_files), do: "Envie um livro por vez."
  defp upload_error(_error), do: "Não foi possível enviar este arquivo."
end
