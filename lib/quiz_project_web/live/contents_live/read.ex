defmodule QuizProjectWeb.ContentsLive.Read do
  @moduledoc """
  Leitor do livro.

  Seção própria, fora de Estudo Adaptativo. Os motivos são concretos: a
  curadoria carrega a árvore inteira e edita, a leitura carrega um capítulo por
  vez e não edita nada; e o estado de cada uma não tem interseção — aqui é
  posição, aparência e filtro, lá é seleção de nó e `dirty?`.

  A ligação entre os dois continua no banco: a demarcação por capítulo aponta
  nós do mapa mental para os blocos que o leitor renderiza.

  O capítulo entra na URL para a posição ser compartilhável e o botão voltar do
  navegador funcionar dentro do livro.
  """
  use QuizProjectWeb, :live_view

  import QuizProjectWeb.Components.Book

  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.AI

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case AdaptiveStudy.get_material(id, user) do
      {:ok, material} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(QuizProject.PubSub, Books.ingest_topic(material.id))
        end

        {:ok,
         socket
         |> assign(
           material: material,
           chapters: Books.list_chapters(material.id),
           saved_position: Books.get_position(user.id, material.id),
           preference: Books.get_preferences(user.id),
           search_term: "",
           results: [],
           ingest_progress: nil,
           contents_open?: false,
           appearance_open?: false,
           confirm_chapter: nil,
           curation_choice: AI.default_selection(),
           usage_chapter: nil,
           highlights: %{},
           highlight_colors: Books.highlight_colors(),
           note_editor: nil,
           notes_open?: false,
           material_highlights: [],
           ai_authorized?: QuizProject.AI.Authorization.authorized?(to_string(user.email))
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Livro não encontrado.")
         |> push_navigate(to: ~p"/contents")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    material = socket.assigns.material

    cond do
      socket.assigns.chapters == [] ->
        {:noreply,
         assign(socket, chapter: nil, blocks: [], covered: %{}, page_title: material.title)}

      chapter = resolve_chapter(socket, params) ->
        {:noreply, load_chapter(socket, chapter)}

      true ->
        {:noreply, push_patch(socket, to: default_path(socket))}
    end
  end

  # Sem capítulo na URL, a leitura continua de onde parou; na primeira vez, no
  # primeiro capítulo de conteúdo — nunca no aviso de copyright.
  defp resolve_chapter(socket, %{"chapter" => raw}) do
    case Integer.parse(raw) do
      {position, ""} -> Enum.find(socket.assigns.chapters, &(&1.position == position))
      _ -> nil
    end
  end

  defp resolve_chapter(_socket, _params), do: nil

  defp default_path(socket) do
    material = socket.assigns.material

    position =
      case socket.assigns.saved_position do
        %{chapter_id: chapter_id} ->
          chapter = Enum.find(socket.assigns.chapters, &(&1.id == chapter_id))
          chapter && chapter.position

        _ ->
          nil
      end

    position = position || Books.first_body_chapter(material.id).position

    ~p"/contents/#{material.id}/#{position}"
  end

  defp load_chapter(socket, chapter) do
    user = socket.assigns.current_user

    socket
    |> assign(
      chapter: chapter,
      blocks: Books.list_blocks(chapter.id),
      covered: Books.coverage(chapter.id),
      highlights: Books.list_highlights(chapter.id, user.id),
      page_title: "#{chapter.title} — #{socket.assigns.material.title}",
      contents_open?: false,
      notes_open?: false,
      # O rascunho aponta para bloco e deslocamento do capítulo anterior — sem
      # fechar aqui, "Salvar" gravaria a nota no capítulo errado.
      note_editor: nil
    )
  end

  # Posição

  @impl true
  def handle_event("save_position", %{"position" => position, "offset" => offset}, socket) do
    %{material: material, chapter: chapter, current_user: user} = socket.assigns

    {:ok, saved} =
      Books.save_position(user.id, material.id, %{
        chapter_id: chapter.id,
        block_position: position,
        offset: offset
      })

    {:noreply, assign(socket, saved_position: saved)}
  end

  # Aparência

  def handle_event("appearance", params, socket) do
    user = socket.assigns.current_user
    preference = socket.assigns.preference

    attrs = %{
      font: atom_param(params["font"], AdaptiveStudy.ReadingPreference.fonts(), preference.font),
      width:
        atom_param(params["width"], AdaptiveStudy.ReadingPreference.widths(), preference.width),
      font_size: int_param(params["font_size"], preference.font_size),
      line_height: int_param(params["line_height"], preference.line_height)
    }

    {:ok, preference} = Books.save_preferences(user.id, attrs)

    {:noreply, assign(socket, preference: preference)}
  end

  # Os painéis se excluem: abertos juntos, um cobriria o outro no telefone, e o
  # Esc fecharia todos de uma vez.
  def handle_event("toggle_appearance", _params, socket) do
    {:noreply,
     assign(socket,
       appearance_open?: not socket.assigns.appearance_open?,
       contents_open?: false,
       notes_open?: false
     )}
  end

  def handle_event("toggle_contents", _params, socket) do
    {:noreply,
     assign(socket,
       contents_open?: not socket.assigns.contents_open?,
       appearance_open?: false,
       notes_open?: false
     )}
  end

  # A lista carrega ao abrir, e não fica sincronizada por PubSub: é o próprio
  # usuário marcando ou apagando, nunca outra aba ou outro processo.
  def handle_event("toggle_notes", _params, socket) do
    open? = not socket.assigns.notes_open?

    socket =
      assign(socket, notes_open?: open?, contents_open?: false, appearance_open?: false)

    socket =
      if open? do
        user = socket.assigns.current_user
        material = socket.assigns.material
        assign(socket, material_highlights: Books.list_highlights_for_material(user.id, material.id))
      else
        socket
      end

    {:noreply, socket}
  end

  # Busca

  def handle_event("search", %{"term" => term}, socket) do
    {:noreply,
     assign(socket,
       search_term: term,
       results: Books.search(socket.assigns.material.id, term, limit: 40)
     )}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_term: "", results: [])}
  end

  # Marcação e notas
  #
  # `create_highlight` é o caminho rápido — cor sem nota, disparado direto da
  # barra flutuante de seleção. `save_note_editor` é o caminho lento — nota
  # com cor, disparado da folha, tanto para criar quanto para editar (o `id`
  # do rascunho decide qual das duas).

  def handle_event(
        "create_highlight",
        %{"block" => position, "start" => start, "end" => end_, "quote" => quote, "color" => color},
        socket
      ) do
    user = socket.assigns.current_user
    chapter = socket.assigns.chapter

    case Books.create_highlight(user, chapter, position, %{
           start_offset: start,
           end_offset: end_,
           quote: String.trim(quote),
           color: highlight_color(socket, color)
         }) do
      {:ok, highlight} -> {:noreply, put_highlight(socket, highlight)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event(
        "open_note_draft",
        %{"block" => position, "start" => start, "end" => end_, "quote" => quote},
        socket
      ) do
    draft = %{
      id: nil,
      block_position: position,
      start_offset: start,
      end_offset: end_,
      quote: String.trim(quote),
      color: :yellow,
      note: ""
    }

    {:noreply,
     assign(socket,
       note_editor: draft,
       contents_open?: false,
       appearance_open?: false,
       notes_open?: false
     )}
  end

  # Reabrir uma marcação existente busca o registro de novo em vez de confiar
  # no que já está desenhado na tela: garante que só o dono edita, mesmo que o
  # clique tenha vindo de uma marca que sobrou de outra sessão de leitura.
  def handle_event("open_highlight", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Books.get_own_highlight(id, user.id) do
      {:ok, highlight} ->
        editor = %{
          id: highlight.id,
          block_position: nil,
          start_offset: highlight.start_offset,
          end_offset: highlight.end_offset,
          quote: highlight.quote,
          color: highlight.color,
          note: highlight.note || ""
        }

        {:noreply,
         assign(socket,
           note_editor: editor,
           contents_open?: false,
           appearance_open?: false,
           notes_open?: false
         )}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_note_color", %{"color" => color}, socket) do
    case socket.assigns.note_editor do
      nil -> {:noreply, socket}
      editor -> {:noreply, assign(socket, note_editor: %{editor | color: highlight_color(socket, color)})}
    end
  end

  def handle_event("cancel_note_editor", _params, socket) do
    {:noreply, assign(socket, note_editor: nil)}
  end

  def handle_event("save_note_editor", %{"note" => note_text}, socket) do
    editor = socket.assigns.note_editor
    note = blank_to_nil(note_text)

    socket =
      case editor.id do
        nil -> create_from_draft(socket, editor, note)
        _ -> update_note(socket, editor, note)
      end

    {:noreply, assign(socket, note_editor: nil)}
  end

  def handle_event("delete_highlight_editor", _params, socket) do
    editor = socket.assigns.note_editor
    socket = if editor && editor.id, do: do_delete_highlight(socket, editor.id), else: socket
    {:noreply, assign(socket, note_editor: nil)}
  end

  def handle_event("delete_highlight_from_list", %{"id" => id}, socket) do
    {:noreply, do_delete_highlight(socket, id)}
  end

  # O botão de IA abre o resumo do processamento antes de gastar: quem clica
  # decide olhando tamanho, provedor, modelo e custo, não só o ícone.
  #
  # A guarda de autorização mora também aqui, e não só no botão desabilitado:
  # o evento chega pelo socket e o clique já desabilitado na tela não impede
  # quem manda o evento direto.
  def handle_event("confirm_curation", %{"id" => chapter_id}, socket) do
    if socket.assigns.ai_authorized? do
      {:noreply,
       assign(socket,
         confirm_chapter: Enum.find(socket.assigns.chapters, &(&1.id == chapter_id)),
         curation_choice: AI.default_selection()
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_curation", _params, socket) do
    {:noreply, assign(socket, confirm_chapter: nil)}
  end

  # O botão do capítulo já processado não navega direto: mostra o que foi
  # gasto antes de sair da leitura, do mesmo jeito que o de processar mostra o
  # que vai ser gasto antes de começar.
  def handle_event("show_usage", %{"id" => chapter_id}, socket) do
    {:noreply,
     assign(socket, usage_chapter: Enum.find(socket.assigns.chapters, &(&1.id == chapter_id)))}
  end

  def handle_event("close_usage", _params, socket) do
    {:noreply, assign(socket, usage_chapter: nil)}
  end

  # Trocar de provedor zera o modelo: o modelo do provedor anterior não existe
  # no novo, e `AI.resolve/2` cai no padrão do provedor escolhido.
  #
  # Combinação que não existe no catálogo é descartada em vez de virar estado,
  # para a tela nunca mostrar uma escolha e o botão agir sobre outra.
  def handle_event("pick_curation", %{"provider" => slug} = params, socket) do
    model = if slug == socket.assigns.curation_choice.provider, do: params["model"]

    case AI.resolve(slug, model) do
      {:ok, _info} -> {:noreply, assign(socket, curation_choice: %{provider: slug, model: model})}
      {:error, _motivo} -> {:noreply, socket}
    end
  end

  # Confirmado. `curate_chapter_async/2` garante em banco que um capítulo só
  # entra em processamento uma vez — aqui só refletimos o estado devolvido,
  # mesmo que o clique tenha chegado tarde demais.
  def handle_event("curate_chapter", %{"id" => chapter_id}, socket) do
    user = socket.assigns.current_user
    escolha = socket.assigns.curation_choice
    socket = assign(socket, confirm_chapter: nil)

    with true <- socket.assigns.ai_authorized?,
         chapter when not is_nil(chapter) <-
           Enum.find(socket.assigns.chapters, &(&1.id == chapter_id)),
         {:ok, %{available?: true} = info} <- AI.resolve(escolha.provider, escolha.model) do
      case Books.curate_chapter_async(chapter, user, provider: info.module, model: info.model) do
        {:ok, updated} ->
          chapters =
            Enum.map(socket.assigns.chapters, fn c ->
              if c.id == updated.id, do: updated, else: c
            end)

          socket = assign(socket, chapters: chapters)

          if socket.assigns.chapter.id == updated.id do
            {:noreply, assign(socket, chapter: updated)}
          else
            {:noreply, socket}
          end

        {:error, :already_processing} ->
          {:noreply, socket}
      end
    else
      # Usuário não autorizado, provedor sem chave, modelo que não é do
      # provedor, capítulo que sumiu: o botão já estava desabilitado para os
      # três primeiros casos, mas o evento chega pelo socket e não se confia
      # nele.
      _ -> {:noreply, socket}
    end
  end

  # A ingestão avisa a cada capítulo, então quem abriu o leitor antes de o livro
  # ficar pronto acompanha o avanço em vez de olhar para uma tela parada.
  @impl true
  def handle_info({:ingest_progress, %{material_id: material_id} = progress}, socket) do
    if material_id == socket.assigns.material.id do
      {:noreply, assign(socket, ingest_progress: progress)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ingest_finished, %{material_id: material_id}}, socket) do
    if material_id == socket.assigns.material.id do
      {:ok, material} =
        AdaptiveStudy.get_material(material_id, socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(material: material, chapters: Books.list_chapters(material_id))
       |> push_patch(to: ~p"/contents/#{material_id}")}
    else
      {:noreply, socket}
    end
  end

  # A curadoria de capítulo roda em background e avisa pelo mesmo tópico da
  # ingestão: atualiza o sumário e, se for o capítulo aberto, também a barra.
  def handle_info({:chapter_curated, %{chapter_id: chapter_id}}, socket) do
    chapters = Books.list_chapters(socket.assigns.material.id)
    socket = assign(socket, chapters: chapters)

    if socket.assigns.chapter && socket.assigns.chapter.id == chapter_id do
      {:noreply, assign(socket, chapter: Enum.find(chapters, &(&1.id == chapter_id)))}
    else
      {:noreply, socket}
    end
  end

  # As rotas de estudo vivem em `live_session :authenticated`, cujo `on_mount`
  # inclui `{UserAuth, :notify_attempts}`. Isto faz a LiveView receber
  # `{:attempt_finished, ...}` e `{:mindmap_generated, ...}` mesmo sem assinar
  # nada — e sem esta cláusula o leitor cairia com `FunctionClauseError`.
  def handle_info(_message, socket), do: {:noreply, socket}

  defp highlight_color(socket, value) do
    Enum.find(socket.assigns.highlight_colors, :yellow, &(to_string(&1) == value))
  end

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Grava a marcação nova no assign por bloco — para a folha de notas e para
  # sobreviver a uma troca de capítulo e volta — e avisa o cliente para
  # desenhar a marca: `push_event` é quem faz o trabalho visual, o assign só
  # mantém a lista consistente.
  defp put_highlight(socket, highlight) do
    socket
    |> update(:highlights, fn highlights ->
      Map.update(highlights, highlight.block_id, [highlight], &(&1 ++ [highlight]))
    end)
    |> push_event("highlight_created", %{
      block_id: highlight.block_id,
      highlight: highlight_payload(highlight)
    })
    |> refresh_material_highlights_if_open()
  end

  defp highlight_payload(highlight) do
    %{
      id: highlight.id,
      start: highlight.start_offset,
      end: highlight.end_offset,
      color: highlight.color,
      note: not is_nil(highlight.note)
    }
  end

  defp create_from_draft(socket, draft, note) do
    user = socket.assigns.current_user
    chapter = socket.assigns.chapter

    case Books.create_highlight(user, chapter, draft.block_position, %{
           start_offset: draft.start_offset,
           end_offset: draft.end_offset,
           quote: draft.quote,
           color: draft.color,
           note: note
         }) do
      {:ok, highlight} -> put_highlight(socket, highlight)
      {:error, _reason} -> socket
    end
  end

  defp update_note(socket, editor, note) do
    user = socket.assigns.current_user

    with {:ok, highlight} <- Books.get_own_highlight(editor.id, user.id),
         {:ok, updated} <- Books.update_highlight(highlight, %{note: note, color: editor.color}) do
      socket
      |> update(:highlights, fn highlights ->
        Map.update(highlights, updated.block_id, [updated], fn list ->
          Enum.map(list, &if(&1.id == updated.id, do: updated, else: &1))
        end)
      end)
      |> push_event("highlight_changed", %{
        id: updated.id,
        color: updated.color,
        note: not is_nil(updated.note)
      })
      |> refresh_material_highlights_if_open()
    else
      _ -> socket
    end
  end

  defp do_delete_highlight(socket, id) do
    user = socket.assigns.current_user

    with {:ok, highlight} <- Books.get_own_highlight(id, user.id),
         :ok <- Books.delete_highlight(highlight) do
      socket
      |> update(:highlights, fn highlights ->
        Map.update(highlights, highlight.block_id, [], fn list ->
          Enum.reject(list, &(&1.id == highlight.id))
        end)
      end)
      |> update(:material_highlights, fn list ->
        Enum.reject(list, &(&1.highlight.id == highlight.id))
      end)
      |> push_event("highlight_deleted", %{id: highlight.id})
    else
      _ -> socket
    end
  end

  defp refresh_material_highlights_if_open(socket) do
    if socket.assigns.notes_open? do
      user = socket.assigns.current_user
      material = socket.assigns.material
      assign(socket, material_highlights: Books.list_highlights_for_material(user.id, material.id))
    else
      socket
    end
  end

  defp atom_param(nil, _allowed, fallback), do: fallback

  defp atom_param(value, allowed, fallback) do
    Enum.find(allowed, fallback, &(to_string(&1) == value))
  end

  defp int_param(nil, fallback), do: fallback

  defp int_param(value, fallback) do
    case Integer.parse(to_string(value)) do
      {number, _} -> number
      :error -> fallback
    end
  end

  defp chapter_index(chapters, chapter) do
    Enum.find_index(chapters, &(&1.id == chapter.id))
  end

  defp neighbour(chapters, chapter, offset) do
    case chapter_index(chapters, chapter) do
      nil -> nil
      index -> Enum.at(chapters, index + offset)
    end
  end

  defp previous_chapter(chapters, chapter) do
    index = chapter_index(chapters, chapter)
    if index && index > 0, do: neighbour(chapters, chapter, -1)
  end

  defp progress(chapters, chapter) do
    case chapter_index(chapters, chapter) do
      nil -> 0
      index -> round((index + 1) / length(chapters) * 100)
    end
  end

  defp column_width(:narrow), do: "58ch"
  defp column_width(:medium), do: "72ch"
  defp column_width(:wide), do: "90ch"

  defp font_stack(:serif), do: "ui-serif, Georgia, 'Times New Roman', serif"
  defp font_stack(:sans), do: "var(--skin-font-body, system-ui), system-ui, sans-serif"
  defp font_stack(:mono), do: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:contents} wide={true}>
      <%= if @chapters == [] do %>
        <.empty material={@material} progress={@ingest_progress} />
      <% else %>
        <link rel="stylesheet" href={~p"/contents/#{@material.id}/book.css"} />

        <.toolbar chapter={@chapter} chapters={@chapters} ai_authorized?={@ai_authorized?} />

        <.appearance_sheet preference={@preference} open?={@appearance_open?} />

        <.curation_dialog
          :if={@confirm_chapter}
          chapter={@confirm_chapter}
          choice={@curation_choice}
        />

        <.usage_dialog :if={@usage_chapter} chapter={@usage_chapter} />

        <.note_sheet editor={@note_editor} colors={@highlight_colors} />

        <%!-- O sumário é navegação, não leitura: fica fora da tela até ser
             chamado, em vez de comer uma coluna fixa ao lado do texto. --%>
        <.contents_drawer
          material={@material}
          chapters={@chapters}
          chapter={@chapter}
          search_term={@search_term}
          results={@results}
          open?={@contents_open?}
        />

        <.notes_drawer material={@material} entries={@material_highlights} open?={@notes_open?} />

        <%!-- As variáveis ficam no quadro, e não no texto, para a navegação de
             rodapé acompanhar a largura de coluna escolhida. --%>
        <div style={"--qreader-width: #{column_width(@preference.width)};
                     --qreader-font: #{font_stack(@preference.font)};
                     --qreader-size: #{@preference.font_size / 100}rem;
                     --qreader-leading: #{@preference.line_height / 100};"}>
          <div
            id="reader-scroll"
            phx-hook=".ReadingPosition"
            data-block={@saved_position && @saved_position.block_position}
            data-offset={@saved_position && @saved_position.offset}
            data-chapter={@saved_position && @saved_position.chapter_id}
            data-current-chapter={@chapter.id}
          >
            <.chapter
              blocks={@blocks}
              covered={@covered}
              highlights={@highlights}
              material_id={@material.id}
              invertible={@material.image_flags}
            />
          </div>

          <.pagination material={@material} chapters={@chapters} chapter={@chapter} />
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".ReadingPosition">
          // A posição é bloco + deslocamento dentro dele, e não percentual de
          // rolagem: mudar fonte, tamanho ou largura de coluna reflui o texto e
          // move o percentual, mas não move o bloco.
          export default {
            mounted() {
              this.measureNav();
              this.restore();
              this.blocks = () => Array.from(this.el.querySelectorAll("[data-position]"));

              this.onScroll = () => {
                clearTimeout(this.timer);
                this.timer = setTimeout(() => this.report(), 600);
              };

              this.onResize = () => this.measureNav();

              window.addEventListener("scroll", this.onScroll, {passive: true});
              window.addEventListener("resize", this.onResize);
            },

            // A navbar muda de altura entre telefone e desktop e entre skins.
            // Sem medir, a barra do capítulo gruda alto demais e deixa uma
            // fresta por onde o texto passa rolando, ou baixa demais e cobre a
            // primeira linha.
            measureNav() {
              const nav = document.querySelector("header.navbar");
              const height = nav ? Math.round(nav.getBoundingClientRect().height) : 64;
              document.documentElement.style.setProperty("--qnav-h", `${height}px`);
            },

            updated() {
              // Trocou de capítulo: volta ao topo em vez de manter a rolagem do
              // anterior, que cairia no meio de um texto que não é mais o mesmo.
              if (this.chapter !== this.el.dataset.currentChapter) { this.restore(); }
            },

            destroyed() {
              window.removeEventListener("scroll", this.onScroll);
              window.removeEventListener("resize", this.onResize);
              clearTimeout(this.timer);
            },

            // Topo útil da tela: abaixo da navbar e da barra do capítulo. É o
            // mesmo ponto que decide qual bloco conta como "onde estou".
            stickyOffset() {
              const nav = parseInt(
                getComputedStyle(document.documentElement).getPropertyValue("--qnav-h"), 10
              ) || 64;
              return nav + 44;
            },

            restore() {
              this.chapter = this.el.dataset.currentChapter;
              const sameChapter = this.el.dataset.chapter === this.chapter;
              const target = sameChapter && this.el.querySelector(
                `[data-position="${this.el.dataset.block}"]`
              );

              if (!target) { return window.scrollTo({top: 0}); }

              const offset = parseFloat(this.el.dataset.offset || "0");
              const rect = target.getBoundingClientRect();
              window.scrollTo({
                top: window.scrollY + rect.top + rect.height * offset - this.stickyOffset()
              });
            },

            report() {
              const marker = this.stickyOffset();
              const visible = this.blocks().find(
                (block) => block.getBoundingClientRect().bottom > marker
              );

              if (!visible) { return; }

              const rect = visible.getBoundingClientRect();
              const offset = rect.height > 0
                ? Math.min(Math.max((marker - rect.top) / rect.height, 0), 1)
                : 0;

              this.pushEvent("save_position", {
                position: parseInt(visible.dataset.position, 10),
                offset: Math.round(offset * 100) / 100
              });
            }
          }
        </script>
      <% end %>
    </Layouts.app>
    """
  end

  attr :material, :map, required: true
  attr :progress, :map, default: nil

  defp empty(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg rounded-3xl border border-base-300 bg-base-100 p-8 text-center">
      <.icon name="hero-book-open" class="mx-auto size-10 opacity-40" />
      <h1 class="mt-3 text-xl font-bold">{@material.title}</h1>

      <div :if={@material.status == "ingesting"} class="mt-2 space-y-2">
        <p class="text-sm opacity-70">
          O livro ainda está sendo processado. Esta página abre sozinha quando terminar.
        </p>
        <div :if={@progress} class="space-y-1">
          <div class="h-1.5 overflow-hidden rounded-full bg-base-200">
            <div
              class="h-full bg-primary transition-all"
              style={"width: #{round(@progress.done / @progress.total * 100)}%"}
            >
            </div>
          </div>
          <p class="truncate text-xs opacity-60">
            Capítulo {@progress.done} de {@progress.total} — {@progress.title}
          </p>
        </div>
      </div>
      <p :if={@material.ingest_error} class="mt-2 text-sm text-error">
        {@material.ingest_error}
      </p>
      <p
        :if={@material.status != "ingesting" and is_nil(@material.ingest_error)}
        class="mt-2 text-sm opacity-70"
      >
        Este material não é um livro em capítulos — ele foi enviado como texto e vive na curadoria.
      </p>

      <.link navigate={~p"/contents"} class="btn btn-primary mt-5 rounded-full px-6">
        Voltar à biblioteca
      </.link>
    </div>
    """
  end

  attr :material, :map, required: true
  attr :chapters, :list, required: true
  attr :chapter, :map, required: true
  attr :search_term, :string, required: true
  attr :results, :list, required: true
  attr :open?, :boolean, required: true

  # O painel fica sempre no DOM, só deslocado para fora da tela: montá-lo a cada
  # abertura perderia o termo já digitado na busca e mataria a transição.
  defp contents_drawer(assigns) do
    ~H"""
    <div
      :if={@open?}
      id="contents-backdrop"
      phx-click="toggle_contents"
      phx-window-keydown="toggle_contents"
      phx-key="escape"
      class="fixed inset-0 z-[60] touch-none bg-base-content/20 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <aside
      id="contents-drawer"
      class={[
        "fixed inset-y-0 left-0 z-[70] flex w-80 max-w-[85vw] flex-col gap-3",
        "border-r border-base-300 bg-base-100 shadow-xl",
        "overscroll-contain p-4 pt-[max(1rem,env(safe-area-inset-top))]",
        "transition-transform duration-200 ease-out motion-reduce:transition-none",
        @open? && "translate-x-0",
        not @open? && "-translate-x-full"
      ]}
      aria-hidden={not @open?}
    >
      <div class="flex items-center justify-between gap-2">
        <.link
          navigate={~p"/contents"}
          class="flex min-w-0 items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3 shrink-0" />
          <span class="truncate">Biblioteca</span>
        </.link>
        <button
          type="button"
          id="close-contents"
          phx-click="toggle_contents"
          class="qreader-tool"
          aria-label="Fechar sumário"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <form id="book-search" phx-change="search" phx-submit="search" class="relative">
        <input
          type="search"
          name="term"
          value={@search_term}
          placeholder="Buscar no livro"
          phx-debounce="300"
          class="input input-sm input-bordered w-full rounded-full pr-8"
        />
        <button
          :if={@search_term != ""}
          type="button"
          phx-click="clear_search"
          class="absolute right-2 top-1/2 -translate-y-1/2 opacity-50 hover:opacity-100"
          aria-label="Limpar busca"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </form>

      <div class="-mx-1 min-h-0 flex-1 overscroll-contain overflow-y-auto px-1">
        <%= if @search_term != "" do %>
          <p class="px-2 pb-2 text-xs font-semibold uppercase tracking-wide opacity-60">
            {length(@results)} ocorrência(s)
          </p>
          <p :if={@results == []} class="px-2 py-4 text-sm opacity-60">
            Nada encontrado para “{@search_term}”.
          </p>
          <.link
            :for={result <- @results}
            patch={result_path(@material, @chapters, result)}
            class="block rounded-xl px-3 py-2 text-xs leading-relaxed hover:bg-base-200"
          >
            {excerpt(result, @search_term)}
          </.link>
        <% else %>
          <p class="px-2 pb-2 text-xs font-semibold uppercase tracking-wide opacity-60">
            Sumário
          </p>
          <.contents chapters={@chapters} current={@chapter} material_id={@material.id} />
        <% end %>
      </div>
    </aside>
    """
  end

  # O resultado da busca aponta para o bloco, e o bloco sabe em que capítulo
  # está: a mesma âncora da posição e do filtro.
  defp result_path(material, chapters, block) do
    chapter = Enum.find(chapters, &(&1.id == block.chapter_id))

    if chapter do
      ~p"/contents/#{material.id}/#{chapter.position}" <> "#block-#{block.position}"
    else
      ~p"/contents/#{material.id}"
    end
  end

  attr :chapter, :map, required: true
  attr :chapters, :list, required: true
  attr :ai_authorized?, :boolean, required: true

  # `--qnav-h` é a altura real da navbar, medida no cliente: ela muda com o
  # ponto de quebra e com a skin, e um `top` chutado deixa uma fresta por onde o
  # texto passa rolando.
  defp toolbar(assigns) do
    assigns = assign(assigns, :ai_state, Books.chapter_ai_state(assigns.chapter))

    ~H"""
    <div class="sticky top-[var(--qnav-h,4rem)] z-30 rounded-2xl border border-base-300 bg-base-100/95 backdrop-blur">
      <%!-- Uma linha só: o título do capítulo é a única informação que a barra
           precisa dar enquanto se lê; o resto são botões que abrem painel. --%>
      <div class="flex items-center gap-1 px-1.5 py-1">
        <button
          type="button"
          id="open-contents"
          phx-click="toggle_contents"
          class="qreader-tool"
          title="Sumário e busca"
          aria-label="Sumário e busca"
        >
          <.icon name="hero-list-bullet" class="size-5" />
        </button>

        <p class="min-w-0 flex-1 truncate text-center text-sm font-semibold">
          {@chapter.title}
        </p>

        <.chapter_ai_button
          chapter={@chapter}
          state={@ai_state}
          risky?={Books.curation_risky?(@chapter.estimated_tokens)}
          authorized?={@ai_authorized?}
        />

        <button
          type="button"
          id="open-notes"
          phx-click="toggle_notes"
          class="qreader-tool"
          title="Minhas anotações"
          aria-label="Minhas anotações"
        >
          <.icon name="hero-bookmark" class="size-5" />
        </button>

        <button
          type="button"
          id="open-appearance"
          phx-click="toggle_appearance"
          class="qreader-tool"
          title="Aparência"
          aria-label="Aparência"
        >
          <.icon name="hero-adjustments-horizontal" class="size-5" />
        </button>
      </div>

      <div class="h-0.5 bg-base-200">
        <div
          class="h-full bg-primary transition-all"
          style={"width: #{progress(@chapters, @chapter)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  attr :chapter, :map, required: true
  attr :state, :atom, required: true
  attr :risky?, :boolean, default: false
  attr :authorized?, :boolean, required: true

  # `:none`/`:failed` disparam o processamento; `:processing` só mostra o
  # andamento (o clique não repete a chamada, o guard já está no servidor);
  # `:done` abre o resumo do que foi gasto, com o link para a curadoria lá
  # dentro — o mesmo motivo do `curation_dialog`, ao contrário: aqui o clique
  # não gasta nada, mas sair da leitura sem saber o que já rodou também não é
  # de graça.
  defp chapter_ai_button(%{state: :done} = assigns) do
    ~H"""
    <button
      type="button"
      id={"chapter-ai-#{@chapter.id}"}
      phx-click="show_usage"
      phx-value-id={@chapter.id}
      class="qreader-tool bg-success/15"
      title="Ver conteúdo de estudo gerado"
      aria-label="Ver conteúdo de estudo gerado"
    >
      <.icon name="hero-sparkles" class="size-5" />
    </button>
    """
  end

  defp chapter_ai_button(%{state: :processing} = assigns) do
    ~H"""
    <span
      id={"chapter-ai-#{@chapter.id}"}
      class="qreader-tool cursor-default opacity-70"
      title="Processando com IA..."
      aria-label="Processando com IA..."
    >
      <.icon name="hero-arrow-path" class="size-5 motion-safe:animate-spin" />
    </span>
    """
  end

  defp chapter_ai_button(%{state: :failed} = assigns) do
    ~H"""
    <button
      type="button"
      id={"chapter-ai-#{@chapter.id}"}
      phx-click="confirm_curation"
      phx-value-id={@chapter.id}
      disabled={not @authorized?}
      class={["qreader-tool bg-error/15", counted?(@chapter) && "qreader-tool-wide"]}
      title={
        if @authorized?,
          do: "Falhou — tentar novamente. " <> curation_hint(@chapter, @risky?),
          else: "Falhou — seu usuário não está autorizado a processar com IA"
      }
      aria-label="Falhou — tentar novamente"
    >
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span :if={counted?(@chapter)} class="qreader-tool-count">
        {compact_tokens(@chapter.estimated_tokens)}
      </span>
    </button>
    """
  end

  defp chapter_ai_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"chapter-ai-#{@chapter.id}"}
      phx-click="confirm_curation"
      phx-value-id={@chapter.id}
      disabled={not @authorized?}
      class={[
        "qreader-tool",
        if(@risky?, do: "bg-warning/20", else: "bg-info/15"),
        counted?(@chapter) && "qreader-tool-wide"
      ]}
      title={
        if @authorized?,
          do: curation_hint(@chapter, @risky?),
          else: "Seu usuário não está autorizado a processar com IA"
      }
      aria-label={
        if @authorized?,
          do: curation_hint(@chapter, @risky?),
          else: "Seu usuário não está autorizado a processar com IA"
      }
    >
      <.icon name="hero-sparkles" class="size-5" />
      <span :if={counted?(@chapter)} class="qreader-tool-count">
        {compact_tokens(@chapter.estimated_tokens)}
      </span>
    </button>
    """
  end

  # O tamanho do capítulo aparece antes do clique, e não depois da falha: o
  # prompt exige decomposição sem perda, então a resposta devolve o texto inteiro
  # e é ela — não a entrada — que arrisca bater no teto do provedor.
  defp curation_hint(chapter, risky?) do
    tamanho = "≈#{format_tokens(chapter.estimated_tokens)} tokens"

    if risky?,
      do: "Processar capítulo com IA (#{tamanho} — capítulo grande, a resposta pode truncar)",
      else: "Processar capítulo com IA (#{tamanho})"
  end

  defp format_tokens(tokens) when tokens >= 1_000_000,
    do: "#{Float.round(tokens / 1_000_000, 1)}M"

  defp format_tokens(tokens) when tokens >= 1_000, do: "#{Float.round(tokens / 1000, 1)}k"
  defp format_tokens(tokens), do: to_string(tokens)

  # O número só aparece enquanto ele decide alguma coisa. Depois de processado o
  # botão vira link para o material gerado, e o tamanho do capítulo deixou de ser
  # uma escolha a fazer.
  defp counted?(%{estimated_tokens: tokens}), do: tokens > 0

  # Provedor local não gasta nada, e modelo fora da tabela de preços não tem
  # custo conhecido — são duas ausências diferentes e a tela diz qual é qual.
  defp cost_label(%{model: nil}, _cost), do: "sem custo — provedor local"
  defp cost_label(_info, :unknown), do: "modelo sem preço tabelado"
  defp cost_label(_info, {:ok, usd}) when usd < 0.01, do: "menos de US$ 0,01"

  defp cost_label(_info, {:ok, usd}) do
    "US$ " <> (usd |> :erlang.float_to_binary(decimals: 2) |> String.replace(".", ","))
  end

  attr :chapter, :map, required: true
  attr :choice, :map, required: true

  # Confirmação antes de gastar. O que decide o clique é o conjunto — tamanho do
  # capítulo, quem vai processar e quanto custa —, então tudo aparece junto, e o
  # que não dá para saber aparece como não sabido.
  #
  # A escolha de provedor e modelo vale só para esta chamada: a configuração
  # global continua mandando em tags, correção, referência e progressão.
  defp curation_dialog(assigns) do
    forecast = Books.curation_forecast(assigns.chapter.estimated_tokens)
    info = resolve_choice(assigns.choice)

    assigns =
      assign(assigns,
        info: info,
        catalog: AI.catalog(),
        forecast: forecast,
        cost: cost_label(info, AI.estimate_cost(info, forecast.input, forecast.output)),
        risky?: Books.curation_risky?(assigns.chapter.estimated_tokens),
        overflow?: info.context != nil and forecast.input > info.context
      )

    ~H"""
    <div
      id="curation-backdrop"
      phx-click="cancel_curation"
      phx-window-keydown="cancel_curation"
      phx-key="escape"
      class="fixed inset-0 z-[80] touch-none bg-base-content/30 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <div
      id="curation-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="curation-dialog-title"
      class={[
        "fixed inset-x-0 bottom-0 z-[90] mx-auto max-h-[90vh] w-full max-w-md overflow-y-auto",
        "rounded-t-3xl border border-base-300 bg-base-100 shadow-2xl",
        "sm:inset-y-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-3xl"
      ]}
    >
      <%!-- Fundo tingido no cabeçalho, e não só no ícone: é o que faz este
           modal (vai gastar) e o de conteúdo já pronto (`usage_dialog/1`, em
           `bg-success/10`) se distinguirem de relance, sem precisar ler o
           texto para saber qual dos dois abriu. --%>
      <div class="flex items-start justify-between gap-2 rounded-t-3xl bg-primary/10 px-5 py-4">
        <div class="flex min-w-0 items-start gap-2">
          <.icon name="hero-sparkles" class="mt-0.5 size-5 shrink-0 text-primary" />
          <div class="min-w-0">
            <h2 id="curation-dialog-title" class="text-sm font-semibold text-primary">
              Processar com IA
            </h2>
            <p class="truncate text-xs opacity-60">{@chapter.title}</p>
          </div>
        </div>
        <button
          type="button"
          id="close-curation"
          phx-click="cancel_curation"
          class="qreader-tool"
          aria-label="Fechar"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <%!-- Os provedores sem chave continuam na lista, e desabilitados: dá para
           comparar preço com quem não está contratado sem poder disparar. --%>
      <form
        id="curation-picker"
        phx-change="pick_curation"
        class="grid gap-3 px-5 pt-4 sm:grid-cols-2"
      >
        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">Provedor</span>
          <select name="provider" class="select select-bordered w-full rounded-full">
            <option
              :for={provider <- @catalog}
              value={provider.slug}
              selected={provider.slug == @info.slug}
            >
              {provider.name}{if provider.available?, do: "", else: " — sem chave"}
            </option>
          </select>
        </label>

        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">Modelo</span>
          <select name="model" id="curation-model" class="select select-bordered w-full rounded-full">
            <option :if={models_of(@catalog, @info.slug) == []} value="">—</option>
            <option
              :for={model <- models_of(@catalog, @info.slug)}
              value={model.id}
              selected={model.id == @info.model}
            >
              {model.id}
            </option>
          </select>
        </label>
      </form>

      <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 px-5 pt-4 text-sm">
        <dt class="opacity-60">Entrada</dt>
        <dd class="text-right font-medium tabular-nums">
          ≈{format_tokens(@forecast.input)} tokens
        </dd>

        <dt class="opacity-60">Saída prevista</dt>
        <dd id="curation-output" class="text-right font-medium tabular-nums">
          ≈{format_tokens(@forecast.output)} tokens
          <span class="block text-[0.65rem] font-normal opacity-60">
            {basis_label(@forecast.basis)}
          </span>
        </dd>

        <dt class="opacity-60">Janela de entrada</dt>
        <dd id="curation-context" class="text-right font-medium tabular-nums">
          {if @info.context, do: "#{format_tokens(@info.context)} tokens", else: "—"}
        </dd>

        <dt class="opacity-60">Preço do modelo</dt>
        <dd id="curation-price" class="text-right font-medium tabular-nums">
          {price_label(@info.pricing)}
        </dd>

        <dt class="opacity-60">Custo estimado</dt>
        <dd id="curation-cost" class="text-right font-medium">{@cost}</dd>

        <dt class="opacity-60">Saldo da conta</dt>
        <dd class="text-right font-medium opacity-60">indisponível</dd>
      </dl>

      <p
        :if={not @info.available?}
        id="curation-unavailable"
        class="mx-5 mt-4 rounded-xl bg-base-200 px-3 py-2 text-xs"
      >
        Sem chave de API configurada para este provedor: dá para comparar o preço, não para
        processar.
      </p>

      <p :if={@overflow?} class="mx-5 mt-4 rounded-xl bg-error/20 px-3 py-2 text-xs">
        O capítulo é maior que a janela de entrada deste modelo: a chamada deve falhar.
      </p>

      <p
        :if={@info.tier == :light}
        id="curation-weak-model"
        class="mx-5 mt-4 rounded-xl bg-warning/20 px-3 py-2 text-xs"
      >
        Modelo da faixa econômica. A decomposição exige devolver o capítulo inteiro em JSON
        estruturado, e modelos assim costumam truncar ou devolver formato inválido — o
        processamento falha, o capítulo volta para o estado anterior e o custo já foi gasto.
      </p>

      <p :if={@risky?} class="mx-5 mt-4 rounded-xl bg-warning/20 px-3 py-2 text-xs">
        Capítulo grande: a resposta precisa devolver o texto inteiro decomposto e pode truncar
        antes do fim.
      </p>

      <%!-- Dito na tela porque a ausência é a informação: sem isto, "saldo:
           indisponível" parece falha de integração, e não limite da API. --%>
      <p class="px-5 pt-4 text-xs leading-relaxed opacity-60">
        A contagem de tokens é estimada, e o custo sai do preço de tabela do modelo — a fatura pode
        diferir. A API de inferência não expõe saldo nem créditos; o relatório de uso fica na Admin
        API, que exige uma chave de administrador separada.
      </p>

      <div class="flex gap-2 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4">
        <button type="button" phx-click="cancel_curation" class="btn btn-ghost flex-1 rounded-full">
          Cancelar
        </button>
        <button
          type="button"
          id="start-curation"
          phx-click="curate_chapter"
          phx-value-id={@chapter.id}
          disabled={not @info.available?}
          class="btn btn-primary flex-1 rounded-full"
        >
          Processar
        </button>
      </div>
    </div>
    """
  end

  attr :chapter, :map, required: true

  # Espelho informativo do `curation_dialog/1`: aqui não há escolha nem clique
  # que gasta — só o que já foi gasto, e o link para o resultado. O
  # `bg-success/10` do cabeçalho é a mesma cor do botão que abre este modal
  # (`bg-success/15` em `chapter_ai_button/1`), e a cor oposta à do modal de
  # processar (`bg-primary/10`) — abrir um conteúdo pronto e começar a gastar
  # de novo não podem parecer a mesma tela.
  defp usage_dialog(assigns) do
    assigns = assign(assigns, :cost, usage_cost(assigns.chapter))

    ~H"""
    <div
      id="usage-backdrop"
      phx-click="close_usage"
      phx-window-keydown="close_usage"
      phx-key="escape"
      class="fixed inset-0 z-[80] touch-none bg-base-content/30 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <div
      id="usage-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="usage-dialog-title"
      class={[
        "fixed inset-x-0 bottom-0 z-[90] mx-auto max-h-[90vh] w-full max-w-md overflow-y-auto",
        "rounded-t-3xl border border-base-300 bg-base-100 shadow-2xl",
        "sm:inset-y-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-3xl"
      ]}
    >
      <div class="flex items-start justify-between gap-2 rounded-t-3xl bg-success/10 px-5 py-4">
        <div class="flex min-w-0 items-start gap-2">
          <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-success" />
          <div class="min-w-0">
            <h2 id="usage-dialog-title" class="text-sm font-semibold text-success">
              Conteúdo já processado
            </h2>
            <p class="truncate text-xs opacity-60">{@chapter.title}</p>
          </div>
        </div>
        <button
          type="button"
          id="close-usage"
          phx-click="close_usage"
          class="qreader-tool"
          aria-label="Fechar"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 px-5 pt-4 text-sm">
        <dt class="opacity-60">Modelo</dt>
        <dd class="text-right font-medium">{@chapter.curated_model || "—"}</dd>

        <dt class="opacity-60">Entrada</dt>
        <dd class="text-right font-medium tabular-nums">
          {usage_tokens_label(@chapter.usage_input_tokens)}
        </dd>

        <dt class="opacity-60">Saída</dt>
        <dd class="text-right font-medium tabular-nums">
          {usage_tokens_label(@chapter.usage_output_tokens)}
        </dd>

        <dt class="opacity-60">Custo</dt>
        <dd class="text-right font-medium">{@cost}</dd>
      </dl>

      <p class="px-5 pt-4 text-xs leading-relaxed opacity-60">
        Uso relatado pelo provedor no momento da curadoria, não uma medição em tempo real — e o
        custo sai do preço de tabela do modelo, não da fatura.
      </p>

      <div class="flex gap-2 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4">
        <button type="button" phx-click="close_usage" class="btn btn-ghost flex-1 rounded-full">
          Fechar
        </button>
        <.link
          navigate={~p"/study/#{@chapter.curated_material_id}/curate"}
          class="btn btn-success flex-1 rounded-full"
        >
          Ver conteúdo
        </.link>
      </div>
    </div>
    """
  end

  attr :editor, :map, default: nil
  attr :colors, :list, required: true

  # Uma folha só para os dois caminhos: `@editor.id` presente é edição (mostra
  # Remover), ausente é a marcação recém-selecionada virando nota (não
  # mostra). O texto marcado aparece em cima, sempre — é o que ancora a nota
  # a um trecho, então some da tela junto com ele.
  defp note_sheet(assigns) do
    ~H"""
    <div
      :if={@editor}
      id="note-backdrop"
      phx-click="cancel_note_editor"
      phx-window-keydown="cancel_note_editor"
      phx-key="escape"
      class="fixed inset-0 z-[80] touch-none bg-base-content/30 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <div
      :if={@editor}
      id="note-editor"
      role="dialog"
      aria-modal="true"
      aria-labelledby="note-editor-title"
      class={[
        "fixed inset-x-0 bottom-0 z-[90] mx-auto max-h-[90vh] w-full max-w-md overflow-y-auto",
        "rounded-t-3xl border border-base-300 bg-base-100 shadow-2xl",
        "sm:inset-y-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-3xl"
      ]}
    >
      <div class="flex items-start justify-between gap-2 rounded-t-3xl bg-primary/10 px-5 py-4 sm:rounded-t-3xl">
        <div class="min-w-0">
          <h2 id="note-editor-title" class="text-sm font-semibold text-primary">
            {if @editor && @editor.id, do: "Editar marcação", else: "Marcar trecho"}
          </h2>
          <p :if={@editor} class="mt-1 line-clamp-2 text-xs italic opacity-70">
            "{@editor.quote}"
          </p>
        </div>
        <button
          type="button"
          id="close-note-editor"
          phx-click="cancel_note_editor"
          class="qreader-tool"
          aria-label="Fechar"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <div :if={@editor} class="flex items-center gap-2 px-5 pt-4">
        <button
          :for={color <- @colors}
          type="button"
          phx-click="pick_note_color"
          phx-value-color={color}
          class={[
            "size-7 rounded-full border-2 transition",
            highlight_swatch_class(color),
            @editor.color == color && "ring-2 ring-offset-2 ring-primary ring-offset-base-100"
          ]}
          aria-label={"Cor #{color}"}
          aria-pressed={@editor.color == color}
        >
        </button>
      </div>

      <form :if={@editor} id="note-form" phx-submit="save_note_editor" class="px-5 pt-4">
        <textarea
          name="note"
          rows="4"
          placeholder="Escreva uma nota sobre este trecho (opcional)"
          class="textarea textarea-bordered w-full rounded-2xl"
        >{@editor.note}</textarea>

        <div class="flex items-center gap-2 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4">
          <button
            :if={@editor.id}
            type="button"
            phx-click="delete_highlight_editor"
            class="btn btn-ghost text-error rounded-full"
          >
            Remover
          </button>
          <span class="flex-1"></span>
          <button type="button" phx-click="cancel_note_editor" class="btn btn-ghost rounded-full">
            Cancelar
          </button>
          <button type="submit" class="btn btn-primary rounded-full px-6">
            Salvar
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp highlight_swatch_class(:yellow), do: "bg-warning border-warning"
  defp highlight_swatch_class(:green), do: "bg-success border-success"
  defp highlight_swatch_class(:blue), do: "bg-info border-info"
  defp highlight_swatch_class(:pink), do: "bg-error border-error"

  attr :material, :map, required: true
  attr :entries, :list, required: true
  attr :open?, :boolean, required: true

  # Lista achatada por livro, e não por capítulo: quem abre esta gaveta quer
  # repassar o que marcou antes de continuar, não navegar pelo sumário de
  # novo — o título do capítulo aparece junto de cada linha para dar contexto
  # sem precisar de uma segunda hierarquia.
  defp notes_drawer(assigns) do
    ~H"""
    <div
      :if={@open?}
      id="notes-backdrop"
      phx-click="toggle_notes"
      phx-window-keydown="toggle_notes"
      phx-key="escape"
      class="fixed inset-0 z-[60] touch-none bg-base-content/20 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <aside
      id="notes-drawer"
      class={[
        "fixed inset-y-0 right-0 z-[70] flex w-80 max-w-[85vw] flex-col gap-3",
        "border-l border-base-300 bg-base-100 shadow-xl",
        "overscroll-contain p-4 pt-[max(1rem,env(safe-area-inset-top))]",
        "transition-transform duration-200 ease-out motion-reduce:transition-none",
        @open? && "translate-x-0",
        not @open? && "translate-x-full"
      ]}
      aria-hidden={not @open?}
    >
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-sm font-semibold">Minhas anotações</h2>
        <button
          type="button"
          id="close-notes"
          phx-click="toggle_notes"
          class="qreader-tool"
          aria-label="Fechar anotações"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <div class="-mx-1 min-h-0 flex-1 overscroll-contain overflow-y-auto px-1">
        <p :if={@entries == []} class="px-2 py-4 text-sm opacity-60">
          Nenhum trecho marcado ainda. Selecione um trecho do texto para marcar ou anotar.
        </p>

        <div
          :for={entry <- @entries}
          :if={entry.chapter}
          class="mb-2 rounded-xl border border-base-300 py-2 pl-3 pr-2"
          style={"border-inline-start: 3px solid var(--color-#{highlight_border_color(entry.highlight.color)})"}
        >
          <.link
            patch={~p"/contents/#{@material.id}/#{entry.chapter.position}" <> "#block-#{entry.block_position}"}
            class="block"
          >
            <p class="truncate text-[0.65rem] font-semibold uppercase tracking-wide opacity-50">
              {entry.chapter.title}
            </p>
            <p class="mt-0.5 line-clamp-2 text-xs italic opacity-80">"{entry.highlight.quote}"</p>
            <p :if={entry.highlight.note} class="mt-1 line-clamp-3 text-xs opacity-70">
              {entry.highlight.note}
            </p>
          </.link>
          <button
            type="button"
            phx-click="delete_highlight_from_list"
            phx-value-id={entry.highlight.id}
            class="mt-1 text-[0.65rem] font-medium text-error/80 hover:text-error"
          >
            Remover
          </button>
        </div>
      </div>
    </aside>
    """
  end

  defp highlight_border_color(:yellow), do: "warning"
  defp highlight_border_color(:green), do: "success"
  defp highlight_border_color(:blue), do: "info"
  defp highlight_border_color(:pink), do: "error"

  defp usage_tokens_label(nil), do: "não registrado"
  defp usage_tokens_label(tokens), do: "#{format_tokens(tokens)} tokens"

  # `nil` de token acontece com o provedor Fake e com corrida que falhou antes
  # de o provedor responder — a mesma distinção nulo/zero do schema do
  # capítulo. Modelo fora da tabela de preço é outra ausência, e vira outra
  # frase, não um custo mudo.
  defp usage_cost(%{usage_input_tokens: nil}), do: "não registrado"
  defp usage_cost(%{usage_output_tokens: nil}), do: "não registrado"

  defp usage_cost(%{usage_input_tokens: input, usage_output_tokens: output, curated_model: model}) do
    case AI.describe_model(model) do
      nil -> "modelo sem preço tabelado"
      info -> cost_label(info, AI.estimate_cost(info, input, output))
    end
  end

  # Renderização não pode quebrar por causa de uma escolha ruim: `pick_curation`
  # já barra o que não existe, e aqui fica a rede embaixo dela.
  defp resolve_choice(%{provider: slug, model: model}) do
    case AI.resolve(slug, model) do
      {:ok, info} ->
        info

      {:error, _motivo} ->
        padrao = AI.default_selection()
        {:ok, info} = AI.resolve(padrao.provider, padrao.model)
        info
    end
  end

  # A previsão de saída começa como suposição e vira média medida assim que há
  # curadoria feita. Dizer qual das duas está valendo é o que separa um número
  # que se pode conferir de um número que se aceita.
  defp basis_label(:assumed), do: "estimado"
  defp basis_label({:measured, 1}), do: "medido em 1 curadoria"
  defp basis_label({:measured, n}), do: "média de #{n} curadorias"

  defp models_of(catalog, slug) do
    case Enum.find(catalog, &(&1.slug == slug)) do
      %{models: models} -> models
      nil -> []
    end
  end

  # Dólares por milhão de tokens, que é a unidade em que os três fabricantes
  # publicam — comparar dois modelos aqui é comparar dois números da mesma
  # tabela, sem conversão no meio. Fica em linha própria, e não dentro da opção
  # do `<select>`, onde o texto ficava espremido e ilegível no telefone.
  defp price_label(nil), do: "—"

  defp price_label(%{input: entrada, output: saida}) do
    "US$ #{trim_zero(entrada)}/#{trim_zero(saida)} por Mtok"
  end

  defp trim_zero(valor) do
    valor |> :erlang.float_to_binary(decimals: 2) |> String.replace(~r/\.?0+$/, "")
  end

  attr :preference, :map, required: true
  attr :open?, :boolean, required: true

  # Painel de aparência como folha de baixo, e não como expansão da barra fixa:
  # quatro controles empurrando a barra para baixo comiam metade da tela do
  # telefone, e os controles ficavam longe do polegar.
  defp appearance_sheet(assigns) do
    ~H"""
    <div
      :if={@open?}
      id="appearance-backdrop"
      phx-click="toggle_appearance"
      phx-window-keydown="toggle_appearance"
      phx-key="escape"
      class="fixed inset-0 z-[60] touch-none bg-base-content/20 backdrop-blur-[1px]"
      aria-hidden="true"
    >
    </div>

    <div
      id="appearance-sheet"
      class={[
        "fixed inset-x-0 bottom-0 z-[70] mx-auto w-full max-w-xl",
        "rounded-t-3xl border border-base-300 bg-base-100 shadow-2xl sm:rounded-3xl sm:mb-4",
        "transition-transform duration-200 ease-out motion-reduce:transition-none",
        @open? && "translate-y-0",
        not @open? && "translate-y-[110%]"
      ]}
      aria-hidden={not @open?}
    >
      <div class="flex items-center justify-between gap-2 px-5 pt-4">
        <h2 class="text-sm font-semibold">Aparência</h2>
        <button
          type="button"
          id="close-appearance"
          phx-click="toggle_appearance"
          class="qreader-tool"
          aria-label="Fechar aparência"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <form
        id="book-appearance"
        phx-change="appearance"
        class="grid gap-5 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-3 sm:grid-cols-2"
      >
        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">Fonte</span>
          <select name="font" class="select select-bordered w-full rounded-full">
            <option value="serif" selected={@preference.font == :serif}>Serifada</option>
            <option value="sans" selected={@preference.font == :sans}>Sem serifa</option>
            <option value="mono" selected={@preference.font == :mono}>Monoespaçada</option>
          </select>
        </label>

        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">
            Largura da coluna
          </span>
          <select name="width" class="select select-bordered w-full rounded-full">
            <option value="narrow" selected={@preference.width == :narrow}>Estreita</option>
            <option value="medium" selected={@preference.width == :medium}>Média</option>
            <option value="wide" selected={@preference.width == :wide}>Larga</option>
          </select>
        </label>

        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">
            Tamanho ({@preference.font_size}%)
          </span>
          <input
            type="range"
            name="font_size"
            min="70"
            max="200"
            step="5"
            value={@preference.font_size}
            class="range range-primary"
          />
        </label>

        <label class="space-y-1.5">
          <span class="text-xs font-semibold uppercase tracking-wide opacity-60">
            Entrelinha ({@preference.line_height / 100})
          </span>
          <input
            type="range"
            name="line_height"
            min="120"
            max="240"
            step="5"
            value={@preference.line_height}
            class="range range-primary"
          />
        </label>
      </form>
    </div>
    """
  end

  attr :material, :map, required: true
  attr :chapters, :list, required: true
  attr :chapter, :map, required: true

  defp pagination(assigns) do
    assigns =
      assign(assigns,
        previous: previous_chapter(assigns.chapters, assigns.chapter),
        next: neighbour(assigns.chapters, assigns.chapter, 1)
      )

    ~H"""
    <nav class="mx-auto flex max-w-[var(--qreader-width)] items-center justify-between gap-3 border-t border-base-200 pt-4">
      <.link
        :if={@previous}
        patch={~p"/contents/#{@material.id}/#{@previous.position}"}
        class="btn btn-ghost max-w-[45%] rounded-full"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        <span class="truncate">{@previous.title}</span>
      </.link>
      <span :if={is_nil(@previous)}></span>

      <.link
        :if={@next}
        patch={~p"/contents/#{@material.id}/#{@next.position}"}
        class="btn btn-ghost max-w-[45%] rounded-full"
      >
        <span class="truncate">{@next.title}</span>
        <.icon name="hero-arrow-right" class="size-4" />
      </.link>
    </nav>
    """
  end
end
