defmodule QuizProjectWeb.Components.Book do
  @moduledoc """
  Renderização dos blocos de um livro.

  Cada bloco vira um elemento com `id="block-<posição>"`, que é a mesma âncora
  usada pela posição de leitura, pela busca e pelo filtro. Nenhuma delas precisa
  procurar texto para achar o trecho.
  """
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]
  import QuizProjectWeb.CoreComponents, only: [icon: 1]

  alias QuizProject.AdaptiveStudy.Block

  attr :blocks, :list, required: true
  attr :material_id, :string, required: true
  attr :covered, :map, default: %{}
  attr :invertible, :map, default: %{}
  attr :highlights, :map, default: %{}

  @doc """
  O corpo do capítulo.

  `covered` é o mapa `block_id => [node_id]` que o filtro consulta, e
  `highlights` é o mesmo desenho para `block_id => [marcação]`. Os dois chegam
  prontos do banco justamente para o render nunca varrer texto.
  """
  def chapter(assigns) do
    ~H"""
    <article id="chapter-body" phx-hook=".Reader" class="qreader-book qprose">
      <.block
        :for={block <- @blocks}
        block={block}
        material_id={@material_id}
        invertible={@invertible}
        nodes={Map.get(@covered, block.id, [])}
        highlights={Map.get(@highlights, block.id, [])}
      />
    </article>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Reader">
      export default {
        mounted() {
          this.initCopy();
          this.initHighlights();
        },

        // Trocar de capítulo troca todos os blocos: os `data-highlights` vêm
        // frescos do servidor no HTML novo, então basta desenhar de novo — o
        // que já mudou de bloco perdeu a marca antiga porque o próprio nó
        // saiu da árvore junto.
        updated() {
          this.applyAllHighlights();
        },

        destroyed() {
          document.removeEventListener("selectionchange", this.onSelectionChange);
          window.removeEventListener("scroll", this.onScroll);
          this.toolbar?.remove();
        },

        // Copiar código
        //
        // Um alvo explícito (o botão do bloco de código) e um implícito (o
        // próprio código inline, que não tem espaço para um botão do lado sem
        // quebrar a linha de texto). O <code> dentro de <pre> fica de fora do
        // segundo caso porque já é coberto pelo primeiro.
        initCopy() {
          this.el.addEventListener("click", (event) => {
            const button = event.target.closest("[data-copy]");
            if (button) { return this.copy(button.dataset.copy, button); }

            const code = event.target.closest("code");
            if (code && !code.closest("pre")) { this.copy(code.textContent, code); }
          });
        },

        copy(text, target) {
          navigator.clipboard.writeText(text);
          clearTimeout(this.copyTimer);
          target.classList.add("qreader-copied");
          this.copyTimer = setTimeout(() => target.classList.remove("qreader-copied"), 1200);
        },

        // Marcação e notas
        //
        // O deslocamento de uma marcação é contado contra o `textContent`
        // renderizado do bloco, não contra o Markdown de `Block.content` — é
        // o cliente quem mede os dois lados (seleção e desenho) contra a
        // mesma régua, então nunca precisa reconciliar com marcação.
        initHighlights() {
          this.applyAllHighlights();

          this.handleEvent("highlight_created", ({ block_id, highlight }) => {
            const block = this.blockEl(block_id);
            if (block) { this.mark(block, highlight); }
          });

          this.handleEvent("highlight_changed", ({ id, color, note }) => {
            const mark = this.el.querySelector(`[data-highlight-id="${id}"]`);
            if (!mark) { return; }
            mark.dataset.color = color;
            mark.dataset.note = note ? "true" : "false";
          });

          this.handleEvent("highlight_deleted", ({ id }) => this.unmark(id));

          this.onSelectionChange = this.debounce(() => this.checkSelection(), 250);
          document.addEventListener("selectionchange", this.onSelectionChange);

          this.onScroll = () => this.hideToolbar();
          window.addEventListener("scroll", this.onScroll, { passive: true });

          this.el.addEventListener("click", (event) => {
            const mark = event.target.closest("[data-highlight-id]");
            if (mark) {
              this.hideToolbar();
              this.pushEvent("open_highlight", { id: mark.dataset.highlightId });
            }
          });
        },

        blockEl(blockId) {
          return this.el.querySelector(`[data-block-id="${blockId}"]`);
        },

        applyAllHighlights() {
          this.el.querySelectorAll("[data-highlights]").forEach((block) => {
            let highlights;
            try {
              highlights = JSON.parse(block.dataset.highlights || "[]");
            } catch (e) {
              highlights = [];
            }
            highlights.forEach((highlight) => this.mark(block, highlight));
          });
        },

        mark(block, highlight) {
          if (block.querySelector(`[data-highlight-id="${highlight.id}"]`)) { return; }

          const range = this.rangeFor(block, highlight.start, highlight.end);
          if (!range) { return; }

          // Deslocamento antigo, ou um bloco cujo Markdown produziu mais de um
          // parágrafo, pode gerar um intervalo que atravessa elementos
          // irmãos — `surroundContents` recusaria por nó parcial, mas o
          // fallback de extrair e reinserir não recusa nada, e embrulhar
          // dois `<p>` num só `<mark>` é o que deforma a página. A marca só
          // é desenhada quando os dois limites tocam o mesmo filho de
          // conteúdo do bloco; atravessar ênfase, link ou código inline
          // continua liberado, porque isso é sempre dentro do mesmo
          // parágrafo. Texto solto entre tags (espaço do próprio molde) não
          // conta como conteúdo, então não decide sozinho que a marca
          // atravessou parágrafo.
          const touched = this.contentChildren(block).filter((child) => range.intersectsNode(child));
          if (touched.length !== 1) { return; }

          const mark = document.createElement("mark");
          mark.className = "qreader-highlight";
          mark.dataset.highlightId = highlight.id;
          mark.dataset.color = highlight.color;
          mark.dataset.note = highlight.note ? "true" : "false";

          try {
            range.surroundContents(mark);
          } catch (e) {
            // A seleção cruza a borda de outro elemento (ênfase, link, código
            // inline) — `surroundContents` recusa mexer em nó parcial, então o
            // conteúdo é extraído e reinserido dentro da marca.
            mark.appendChild(range.extractContents());
            range.insertNode(mark);
          }
        },

        // Filhos diretos do bloco que carregam conteúdo de verdade — ignora
        // nó de texto só de espaço, que é formatação do molde, não algo que
        // alguém selecionou.
        contentChildren(root) {
          return Array.from(root.childNodes).filter(
            (child) => !(child.nodeType === Node.TEXT_NODE && child.nodeValue.trim() === "")
          );
        },

        unmark(id) {
          const mark = this.el.querySelector(`[data-highlight-id="${id}"]`);
          if (!mark) { return; }
          const parent = mark.parentNode;
          while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
          parent.removeChild(mark);
          parent.normalize();
        },

        rangeFor(root, start, end) {
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          const range = document.createRange();
          let pos = 0, started = false, node;

          while ((node = walker.nextNode())) {
            const nodeStart = pos;
            const nodeEnd = pos + node.nodeValue.length;

            if (!started && end > nodeStart && start <= nodeEnd) {
              range.setStart(node, Math.max(0, start - nodeStart));
              started = true;
            }
            if (started && end <= nodeEnd) {
              range.setEnd(node, end - nodeStart);
              return range;
            }
            pos = nodeEnd;
          }
          return null;
        },

        // O limite de uma seleção nem sempre cai num nó de texto: clique
        // triplo, "selecionar parágrafo" e alguns gestos de toque no celular
        // devolvem um elemento com `offset` contando filhos, não caracteres.
        // Um `TreeWalker` só visita texto, então `node === container` nunca
        // batia nesse caso e a busca caía no fim do bloco inteiro — a marca
        // saía deslocada ou cobrindo o bloco todo. O próprio `Range` resolve
        // os dois formatos igual, contando o texto que ele mesmo abrange.
        textOffset(root, container, offset) {
          const range = document.createRange();
          range.selectNodeContents(root);
          range.setEnd(container, offset);
          return range.toString().length;
        },

        checkSelection() {
          const selection = document.getSelection();
          if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
            return this.hideToolbar();
          }

          const range = selection.getRangeAt(0);
          const block = this.singleBlock(range);
          const text = selection.toString().trim();
          // Bloco de código já tem seleção com outro propósito — copiar o
          // trecho exato para colar num terminal —, e o próprio clique em
          // código inline dispara isso (`initCopy`). Marcar por cima
          // misturaria as duas ações no mesmo gesto.
          if (!block || block.dataset.type === "code" || text === "") { return this.hideToolbar(); }

          const start = this.textOffset(block, range.startContainer, range.startOffset);
          const end = this.textOffset(block, range.endContainer, range.endOffset);
          if (end <= start) { return this.hideToolbar(); }

          this.showToolbar(range, { block: Number(block.dataset.position), start, end, quote: text });
        },

        // A seleção só vira marcação se começar e terminar dentro do mesmo
        // bloco — a mesma granularidade que a IA já demarca — e evita
        // reconciliar um intervalo contra dois textos de blocos diferentes.
        singleBlock(range) {
          const startEl = range.startContainer.nodeType === Node.TEXT_NODE
            ? range.startContainer.parentElement
            : range.startContainer;
          const endEl = range.endContainer.nodeType === Node.TEXT_NODE
            ? range.endContainer.parentElement
            : range.endContainer;

          const startBlock = startEl?.closest?.("[data-position]");
          const endBlock = endEl?.closest?.("[data-position]");

          return startBlock && startBlock === endBlock ? startBlock : null;
        },

        showToolbar(range, selection) {
          const toolbar = this.toolbarEl();
          toolbar.dataset.pending = JSON.stringify(selection);
          toolbar.style.display = "flex";

          const rect = range.getBoundingClientRect();
          const width = toolbar.offsetWidth;
          const height = toolbar.offsetHeight;
          // Em touch (tablet/celular), o menu nativo de seleção (copiar,
          // selecionar tudo...) ocupa o espaço acima do trecho — nosso menu
          // precisa aparecer abaixo pra não ficar tampado por ele.
          const coarsePointer = window.matchMedia("(pointer: coarse)").matches;
          const top = coarsePointer
            ? Math.min(window.innerHeight - height - 8, rect.bottom + 10)
            : Math.max(8, rect.top - height - 10);
          const left = Math.min(
            Math.max(8, rect.left + rect.width / 2 - width / 2),
            window.innerWidth - width - 8
          );
          toolbar.style.top = `${top}px`;
          toolbar.style.left = `${left}px`;
        },

        hideToolbar() {
          if (this.toolbar) { this.toolbar.style.display = "none"; }
        },

        toolbarEl() {
          if (this.toolbar) { return this.toolbar; }

          const toolbar = document.createElement("div");
          toolbar.className = "qreader-toolbar";
          toolbar.innerHTML = `
            <button type="button" data-color="yellow" aria-label="Marcar em amarelo"></button>
            <button type="button" data-color="green" aria-label="Marcar em verde"></button>
            <button type="button" data-color="blue" aria-label="Marcar em azul"></button>
            <button type="button" data-color="pink" aria-label="Marcar em rosa"></button>
            <button type="button" data-note aria-label="Marcar e anotar">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
            </button>
          `;

          // `mousedown` dispara antes do `click` e colapsaria a seleção antes
          // de o botão poder lê-la — a seleção já foi guardada em
          // `dataset.pending` quando a barra apareceu, então só falta este
          // evento não atrapalhar.
          toolbar.addEventListener("mousedown", (event) => event.preventDefault());
          toolbar.addEventListener("click", (event) => {
            const button = event.target.closest("button");
            if (!button) { return; }

            const selection = JSON.parse(toolbar.dataset.pending || "null");
            if (!selection) { return; }

            if (button.dataset.note !== undefined) {
              this.pushEvent("open_note_draft", selection);
            } else {
              this.pushEvent("create_highlight", { ...selection, color: button.dataset.color });
            }

            document.getSelection()?.removeAllRanges();
            this.hideToolbar();
          });

          document.body.appendChild(toolbar);
          this.toolbar = toolbar;
          return toolbar;
        },

        debounce(fn, wait) {
          let timer;
          return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn(...args), wait);
          };
        }
      }
    </script>
    """
  end

  attr :block, :map, required: true
  attr :material_id, :string, required: true
  attr :nodes, :list, default: []
  attr :invertible, :map, default: %{}
  attr :highlights, :list, default: []

  def block(assigns) do
    assigns =
      assigns
      |> assign(:covered?, assigns.nodes != [])
      |> assign(:highlights_json, highlights_json(assigns.highlights))

    ~H"""
    <div
      id={"block-#{@block.position}"}
      data-position={@block.position}
      data-block-id={@block.id}
      data-type={@block.type}
      data-nodes={Enum.join(@nodes, " ")}
      data-highlights={@highlights_json}
      class={["qreader-block", @covered? && "qreader-covered"]}
    ><%!--
      Sem quebra de linha entre a tag e o conteúdo de propósito: a
      indentação do template vira nó de texto de verdade no HTML (não é só
      estética do código), e esse texto solto conta como caractere para
      quem mede seleção — a marcação saía deslocada do começo real do
      parágrafo por causa da própria formatação deste arquivo.
    --%>{render_body(assigns)}</div>
    """
  end

  # O hook lê isto uma vez, ao montar ou trocar de capítulo, para desenhar as
  # marcas sem esperar round-trip nenhum — criar, editar e apagar depois disso
  # acontece por `push_event`, não por reler este atributo.
  defp highlights_json([]), do: "[]"

  defp highlights_json(highlights) do
    highlights
    |> Enum.map(
      &%{
        id: &1.id,
        start: &1.start_offset,
        end: &1.end_offset,
        color: &1.color,
        note: not is_nil(&1.note)
      }
    )
    |> Jason.encode!()
  end

  defp render_body(%{block: %{type: :code}} = assigns) do
    assigns = assign(assigns, :code, strip_prompt(assigns.block.content))

    ~H"""
    <figure class="qreader-listing">
      <figcaption :if={@block.caption} class="qreader-listing-title">
        {@block.caption}
      </figcaption>
      <div class="qreader-code-wrap">
        <pre class="code-area"><code class={@block.lang && "language-#{@block.lang}"}>{@code}</code></pre>
        <button
          type="button"
          class="qreader-copy"
          data-copy={@code}
          aria-label="Copiar código"
          title="Copiar código"
        >
          <.icon name="hero-clipboard-document" class="size-4" />
        </button>
      </div>
      <ol :if={@block.annotations != []} class="qreader-annotations">
        <li :for={annotation <- @block.annotations}>{annotation}</li>
      </ol>
    </figure>
    """
  end

  defp render_body(%{block: %{type: :figure}} = assigns) do
    ~H"""
    <figure class="qreader-figure">
      <%!-- `loading="lazy"` porque um capítulo denso traz dezenas de diagramas e
            nem todos entram na tela. O lugar reservado cobre o EPUB que aponta
            para uma imagem que o pacote não traz. --%>
      <img
        :if={@block.image_path}
        src={image_url(@material_id, @block.image_path)}
        alt={List.first(@block.annotations) || @block.caption || ""}
        class={if Map.has_key?(@invertible, @block.image_path), do: "qreader-invertible"}
        loading="lazy"
        decoding="async"
      />
      <div :if={is_nil(@block.image_path)} class="qreader-figure-placeholder">
        <span>Figura não incluída neste EPUB</span>
      </div>
      <figcaption :if={@block.caption}>{@block.caption}</figcaption>
    </figure>
    """
  end

  defp render_body(%{block: %{type: :sidebar}} = assigns) do
    ~H"""
    <aside class="qreader-sidebar">{markdown(@block.content, @material_id, @invertible)}</aside>
    """
  end

  defp render_body(%{block: %{type: :callout}} = assigns) do
    ~H"""
    <aside class="qreader-callout">{markdown(@block.content, @material_id, @invertible)}</aside>
    """
  end

  defp render_body(%{block: %{type: :list_item}} = assigns) do
    ~H"""
    <ul class="qreader-list">
      <li>{markdown(@block.content, @material_id, @invertible)}</li>
    </ul>
    """
  end

  defp render_body(assigns) do
    ~H"""
    {markdown(@block.content, @material_id, @invertible)}
    """
  end

  # O bloco já chega em Markdown, então a renderização é a mesma do resto do
  # material. As extensões ligadas aqui são as que a ingestão produz: tabela em
  # GFM, e nada de HTML cru vindo do arquivo do usuário.
  defp markdown(content, material_id, invertible) do
    case MDEx.to_html(content,
           extension: [table: true, strikethrough: true],
           render: [escape: false, unsafe: false]
         ) do
      {:ok, html} -> html |> rewrite_images(material_id, invertible) |> raw()
      {:error, _reason} -> content
    end
  end

  # A imagem no meio da frase guarda o caminho de dentro do EPUB, não uma URL da
  # aplicação — o bloco é a única cópia do texto e não deve depender do esquema
  # de rotas. A tradução acontece aqui, e só para caminho interno: `src` absoluto
  # ou com esquema passa intacto.
  defp rewrite_images(html, material_id, invertible) do
    Regex.replace(~r/src="(?!https?:|data:|\/)([^"]*)"/, html, fn _match, path ->
      classe = if Map.has_key?(invertible, path), do: ~s( class="qreader-invertible"), else: ""
      ~s(src="#{image_url(material_id, path)}"#{classe})
    end)
  end

  defp image_url(material_id, path), do: "/contents/#{material_id}/images/#{path}"

  # Livros costumam reproduzir o prompt do terminal junto com o comando ("$ npm
  # install"), útil impresso e inútil colado — quem cola vê o "$" como parte do
  # comando e o shell recusa. A tira só quando "$ " abre a linha: no meio dela é
  # variável de shell ou de PHP, não prompt.
  defp strip_prompt(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.replace(&1, ~r/^\$ /, ""))
    |> Enum.join("\n")
  end

  attr :chapters, :list, required: true
  attr :current, :map, required: true
  attr :material_id, :string, required: true

  @doc "Sumário do livro, com o pré-textual separado do corpo."
  def contents(assigns) do
    ~H"""
    <nav class="space-y-0.5">
      <.link
        :for={chapter <- @chapters}
        patch={"/contents/#{@material_id}/#{chapter.position}"}
        class={[
          "block rounded-xl py-2.5 pr-3 transition",
          nesting_class(chapter.level),
          chapter.id == @current.id && "bg-primary/10 font-semibold text-primary",
          chapter.id != @current.id && "hover:bg-base-200"
        ]}
      >
        <span class="flex items-baseline justify-between gap-2">
          <span class={[chapter.kind != :body && "opacity-60"]}>{chapter.title}</span>
          <%!-- Tokens estimados, e não número de blocos: bloco conta título de
               duas palavras igual a listagem de 40 linhas, então media estrutura
               em vez de esforço. É também o mesmo número que o botão de IA usa,
               para a tela não dar duas medidas de tamanho que discordam. --%>
          <span
            :if={chapter.estimated_tokens > 0}
            class="shrink-0 text-[0.65rem] tabular-nums opacity-50"
          >
            {compact_tokens(chapter.estimated_tokens)}
          </span>
        </span>
      </.link>
    </nav>
    """
  end

  @doc """
  Contagem de tokens em forma curta, para caber ao lado de um título.

  Vive aqui, e não no LiveView do leitor, porque o sumário e o botão de IA
  mostram o mesmo número e não podem arredondar de jeitos diferentes.
  """
  def compact_tokens(tokens) when tokens >= 1_000_000,
    do: "#{Float.round(tokens / 1_000_000, 1)}M"

  def compact_tokens(tokens) when tokens >= 1_000, do: "#{round(tokens / 1000)}k"
  def compact_tokens(tokens), do: to_string(tokens)

  # `chapters` é uma tabela achatada, não uma árvore — mas o nível que o nav/NCX
  # do próprio livro declarou continua em `chapter.level`. Sem usar isso, um
  # livro com Parte > Capítulo > Seção (ex.: "Machine Learning in Elixir") sai
  # como uma centena de linhas na mesma indentação, com títulos genéricos tipo
  # "Wrapping Up" repetidos a cada capítulo sem nenhuma pista de qual é qual.
  # Nível 1 fica do jeito que sempre foi — é o único nível na maioria dos
  # livros — e só a partir do nível 2 o recuo e o texto menor entram.
  defp nesting_class(1), do: "pl-3 text-sm"
  defp nesting_class(2), do: "pl-6 text-[0.8125rem]"
  defp nesting_class(level) when is_integer(level) and level >= 3, do: "pl-9 text-xs opacity-90"
  defp nesting_class(_), do: "pl-3 text-sm"

  @doc "Trecho de um bloco para a lista de resultados da busca, centrado no termo."
  def excerpt(block, term) do
    content = block.content |> Block.plain_text() |> String.replace(~r/\s+/u, " ")

    case String.split(String.downcase(content), String.downcase(term), parts: 2) do
      [before, _rest] ->
        start = max(String.length(before) - 60, 0)
        trecho = String.slice(content, start, 220)
        if start > 0, do: "…" <> trecho, else: trecho

      _ ->
        String.slice(content, 0, 180)
    end
  end
end
