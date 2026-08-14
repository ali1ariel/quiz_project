defmodule QuizProjectWeb.ContentsLive.Index do
  @moduledoc """
  Biblioteca: os livros do usuário, e por onde se volta à leitura.

  O cartão mostra o que interessa a quem vai ler — onde parou e quanto falta —
  e não o que interessa a quem cura material de estudo.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Conteúdos") |> load_books()}
  end

  @impl true
  def handle_event("delete_book", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case AdaptiveStudy.get_material(id, user) do
      {:ok, book} ->
        {:ok, _} = AdaptiveStudy.delete_material(book, user)

        {:noreply,
         socket
         |> put_flash(:info, "\"#{book.title}\" foi removido da biblioteca.")
         |> load_books()}

      _ ->
        {:noreply, put_flash(socket, :error, "Livro não encontrado.")}
    end
  end

  # A ingestão avisa pelo tópico do usuário que o `on_mount` já assina, então o
  # cartão sai de "Lendo o livro..." sozinho quando o processamento termina.
  @impl true
  def handle_info({:ingest_finished, _info}, socket), do: {:noreply, load_books(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_books(socket) do
    user = socket.assigns.current_user
    books = AdaptiveStudy.list_books(user)

    assign(socket,
      books: books,
      # Medido em capítulos, não em blocos: mais exato em blocos, mais útil em
      # capítulos, que é como quem lê pensa em "onde estou".
      progress: Books.library_progress(user.id, Enum.map(books, & &1.id))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:contents}>
      <div class="space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-3 border-b border-base-300 pb-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Conteúdos</h1>
            <p class="text-sm opacity-70">
              Seus livros, prontos para ler. A leitura continua de onde parou, em qualquer aparelho.
            </p>
          </div>
          <.link
            id="new-book-btn"
            navigate={~p"/contents/new"}
            class="btn btn-primary rounded-full px-6 max-sm:w-full"
          >
            <.icon name="hero-plus" class="size-4" /> Adicionar livro
          </.link>
        </div>

        <%= if @books == [] do %>
          <div class="rounded-3xl border border-dashed border-base-300 p-10 text-center">
            <.icon name="hero-book-open" class="mx-auto size-10 opacity-40" />
            <h2 class="mt-3 text-lg font-bold">Nenhum livro na biblioteca</h2>
            <p class="mx-auto mt-1 max-w-md text-sm opacity-70">
              Envie um arquivo <code>.epub</code>
              e ele será dividido em capítulos e blocos para leitura — sem DRM e sem layout fixo.
            </p>
            <.link navigate={~p"/contents/new"} class="btn btn-primary mt-5 rounded-full px-6">
              Adicionar o primeiro
            </.link>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <.book_card :for={book <- @books} book={book} progress={@progress[book.id]} />
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :book, :map, required: true
  attr :progress, :map, required: true

  defp book_card(assigns) do
    %{total: total, current: current} = assigns.progress

    assigns =
      assign(assigns,
        current: current,
        total: total,
        percent: if(total > 0 and current, do: round(current / total * 100), else: 0),
        ready?: assigns.book.status not in ~w(ingesting failed)
      )

    ~H"""
    <div
      id={"book-card-#{@book.id}"}
      class="card qcard flex flex-col gap-3 border border-base-300 bg-base-100 p-5 transition hover:shadow-md"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="line-clamp-2 text-lg font-bold leading-snug">{@book.title}</h2>
          <p :if={@book.author} class="mt-0.5 truncate text-xs opacity-60">{@book.author}</p>
        </div>
        <button
          id={"delete-book-#{@book.id}"}
          phx-click="delete_book"
          phx-value-id={@book.id}
          data-confirm="Remover este livro da biblioteca? O texto extraído será apagado."
          class="qreader-tool -mr-2 -mt-1 text-error/70 hover:text-error"
          title="Remover livro"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </div>

      <p :if={@book.ingest_error} class="text-xs text-error">{@book.ingest_error}</p>

      <div :if={@book.status == "ingesting"} class="flex items-center gap-2 text-xs opacity-70">
        <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Lendo o livro...
      </div>

      <div :if={@ready?} class="mt-auto space-y-2">
        <div class="h-1 overflow-hidden rounded-full bg-base-200">
          <div class="h-full bg-primary transition-all" style={"width: #{@percent}%"}></div>
        </div>
        <div class="flex items-center justify-between gap-3 text-xs opacity-70">
          <span>
            {if @current, do: "Capítulo #{@current} de #{@total}", else: "#{@total} capítulos"}
          </span>
          <.link
            id={"read-link-#{@book.id}"}
            navigate={~p"/contents/#{@book.id}"}
            class="-my-1 -mr-2 inline-flex min-h-11 items-center gap-1 rounded-full px-3 text-sm font-semibold text-primary transition hover:bg-primary/10"
          >
            {if @current, do: "Continuar", else: "Ler"}
            <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
