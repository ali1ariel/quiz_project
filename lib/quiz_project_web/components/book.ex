defmodule QuizProjectWeb.Components.Book do
  @moduledoc """
  Renderização dos blocos de um livro.

  Cada bloco vira um elemento com `id="block-<posição>"`, que é a mesma âncora
  usada pela posição de leitura, pela busca e pelo filtro. Nenhuma delas precisa
  procurar texto para achar o trecho.
  """
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  alias QuizProject.AdaptiveStudy.Block

  attr :blocks, :list, required: true
  attr :covered, :map, default: %{}

  @doc """
  O corpo do capítulo.

  `covered` é o mapa `block_id => [node_id]` que o filtro consulta. Ele chega
  pronto do banco justamente para o render nunca varrer texto.
  """
  def chapter(assigns) do
    ~H"""
    <article class="qreader-book qprose">
      <.block :for={block <- @blocks} block={block} nodes={Map.get(@covered, block.id, [])} />
    </article>
    """
  end

  attr :block, :map, required: true
  attr :nodes, :list, default: []

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
    ~H"""
    <figure class="qreader-listing">
      <figcaption :if={@block.caption} class="qreader-listing-title">
        {@block.caption}
      </figcaption>
      <pre class="code-area"><code class={@block.lang && "language-#{@block.lang}"}>{@block.content}</code></pre>
      <ol :if={@block.annotations != []} class="qreader-annotations">
        <li :for={annotation <- @block.annotations}>{annotation}</li>
      </ol>
    </figure>
    """
  end

  defp render_body(%{block: %{type: :figure}} = assigns) do
    ~H"""
    <%!-- Imagens ficam fora da v1: o que sobrevive é a legenda e o texto
          alternativo, para o leitor saber que havia uma figura ali. --%>
    <figure class="qreader-figure">
      <div class="qreader-figure-placeholder">
        <span>Figura não incluída nesta versão</span>
      </div>
      <figcaption :if={@block.caption}>{@block.caption}</figcaption>
      <p :for={alt <- @block.annotations} class="qreader-figure-alt">{alt}</p>
    </figure>
    """
  end

  defp render_body(%{block: %{type: :sidebar}} = assigns) do
    ~H"""
    <aside class="qreader-sidebar">{markdown(@block.content)}</aside>
    """
  end

  defp render_body(%{block: %{type: :callout}} = assigns) do
    ~H"""
    <aside class="qreader-callout">{markdown(@block.content)}</aside>
    """
  end

  defp render_body(%{block: %{type: :list_item}} = assigns) do
    ~H"""
    <ul class="qreader-list">
      <li>{markdown(@block.content)}</li>
    </ul>
    """
  end

  defp render_body(assigns) do
    ~H"""
    {markdown(@block.content)}
    """
  end

  # O bloco já chega em Markdown, então a renderização é a mesma do resto do
  # material. As extensões ligadas aqui são as que a ingestão produz: tabela em
  # GFM, e nada de HTML cru vindo do arquivo do usuário.
  defp markdown(content) do
    case MDEx.to_html(content,
           extension: [table: true, strikethrough: true],
           render: [escape: false, unsafe: false]
         ) do
      {:ok, html} -> raw(html)
      {:error, _reason} -> content
    end
  end

  attr :chapters, :list, required: true
  attr :current, :map, required: true
  attr :material_id, :string, required: true

  @doc "Sumário do livro, com o pré-textual separado do corpo."
  def contents(assigns) do
    ~H"""
    <nav class="space-y-1">
      <.link
        :for={chapter <- @chapters}
        patch={"/contents/#{@material_id}/#{chapter.position}"}
        class={[
          "block rounded-xl px-3 py-2.5 text-sm transition",
          chapter.id == @current.id && "bg-primary/10 font-semibold text-primary",
          chapter.id != @current.id && "hover:bg-base-200"
        ]}
      >
        <span class="flex items-baseline justify-between gap-2">
          <span class={[chapter.kind != :body && "opacity-60"]}>{chapter.title}</span>
          <span class="shrink-0 text-[0.65rem] tabular-nums opacity-50">
            {chapter.block_count}
          </span>
        </span>
      </.link>
    </nav>
    """
  end

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
