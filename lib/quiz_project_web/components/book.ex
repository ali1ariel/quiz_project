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

  @doc """
  O corpo do capítulo.

  `covered` é o mapa `block_id => [node_id]` que o filtro consulta. Ele chega
  pronto do banco justamente para o render nunca varrer texto.
  """
  def chapter(assigns) do
    ~H"""
    <article id="chapter-body" phx-hook=".CopyCode" class="qreader-book qprose">
      <.block
        :for={block <- @blocks}
        block={block}
        material_id={@material_id}
        invertible={@invertible}
        nodes={Map.get(@covered, block.id, [])}
      />
    </article>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyCode">
      // Um alvo explícito (o botão do bloco de código) e um implícito (o
      // próprio código inline, que não tem espaço para um botão do lado sem
      // quebrar a linha de texto). O <code> dentro de <pre> fica de fora do
      // segundo caso porque já é coberto pelo primeiro.
      export default {
        mounted() {
          this.el.addEventListener("click", (event) => {
            const button = event.target.closest("[data-copy]")
            if (button) { return this.copy(button.dataset.copy, button) }

            const code = event.target.closest("code")
            if (code && !code.closest("pre")) { this.copy(code.textContent, code) }
          })
        },

        copy(text, target) {
          navigator.clipboard.writeText(text)
          clearTimeout(this.timer)
          target.classList.add("qreader-copied")
          this.timer = setTimeout(() => target.classList.remove("qreader-copied"), 1200)
        }
      }
    </script>
    """
  end

  attr :block, :map, required: true
  attr :material_id, :string, required: true
  attr :nodes, :list, default: []
  attr :invertible, :map, default: %{}

  def block(assigns) do
    assigns = assign(assigns, :covered?, assigns.nodes != [])

    ~H"""
    <div
      id={"block-#{@block.position}"}
      data-position={@block.position}
      data-type={@block.type}
      data-nodes={Enum.join(@nodes, " ")}
      class={["qreader-block", @covered? && "qreader-covered"]}
    >
      {render_body(assigns)}
    </div>
    """
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
