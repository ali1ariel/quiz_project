defmodule QuizProjectWeb.AdaptiveStudyLive.Mindmap do
  @moduledoc """
  Canvas de navegação do Mapa Mental.

  As posições vêm prontas de `QuizProject.AdaptiveStudy.MindmapLayout`; aqui só
  desenhamos: as arestas em um `<svg>` de fundo e os nós como botões HTML
  posicionados em absoluto por cima — assim o cartão continua sendo um elemento
  normal (Tailwind, `phx-click`, truncamento de texto) e as ligações ganham
  curvas de verdade.

  O JavaScript cuida apenas de pan e zoom: seleção, recolhimento de ramos e
  edição continuam sendo eventos da LiveView.
  """
  use QuizProjectWeb, :html

  alias QuizProject.AdaptiveStudy

  attr :layout, :map, required: true
  attr :selected_id, :string, default: nil
  attr :origin_id, :string, default: nil

  def canvas(assigns) do
    # Na árvore as relações transversais só entram em cena quando um nó é
    # selecionado: por padrão a tela mostra a formação da árvore e nada mais.
    assigns =
      assign(assigns,
        relations: visible_relations(assigns.layout, assigns.selected_id),
        ctx: context(assigns)
      )

    ~H"""
    <div
      id="mindmap-canvas"
      phx-hook=".MindmapPanZoom"
      data-width={@layout.width}
      data-height={@layout.height}
      data-signature={@layout.signature}
      class="absolute inset-0 touch-none select-none overflow-hidden bg-base-200/60 [background-image:radial-gradient(circle,var(--color-base-300)_1px,transparent_1px)] [background-size:26px_26px]"
    >
      <div id="mindmap-stage" class="absolute left-0 top-0 origin-top-left">
        <svg
          width={@layout.width}
          height={@layout.height}
          viewBox={"0 0 #{@layout.width} #{@layout.height}"}
          class="pointer-events-none absolute left-0 top-0"
        >
          <path
            :for={edge <- @layout.edges}
            d={edge.path}
            fill="none"
            stroke-width="2"
            class={[
              "stroke-current text-base-content/25 transition-opacity duration-200",
              edge_opacity(edge, @ctx)
            ]}
          />

          <%!-- Porta de entrada: o ponto na frente do cartão onde a ligação do pai
               chega. A de saída é o próprio alternador de ramo, na borda de trás. --%>
          <circle
            :for={node <- Enum.filter(@layout.nodes, &(&1.depth > 0))}
            :if={@layout.mode == :tree}
            cx={node.x - @layout.node_width / 2 - 8}
            cy={node.y}
            r="3.5"
            class={[
              "fill-current text-base-content/40 transition-opacity duration-200",
              node_opacity(node, @ctx)
            ]}
          />

          <g
            :for={relation <- @relations}
            class={[
              relation_color(relation.type),
              "transition-opacity duration-200",
              edge_opacity(relation, @ctx)
            ]}
          >
            <path
              d={relation.path}
              fill="none"
              stroke-width="1.75"
              stroke-dasharray="6 5"
              class="stroke-current"
            />
            <circle cx={relation.from_x} cy={relation.from_y} r="3" class="fill-current" />
            <circle cx={relation.to_x} cy={relation.to_y} r="4.5" class="fill-current" />
            <text
              x={relation.label_x}
              y={relation.label_y}
              text-anchor="middle"
              dominant-baseline="middle"
              class="fill-current text-[10px] font-semibold"
            >
              {relation_text(relation)}
            </text>
          </g>
        </svg>

        <button
          :for={node <- @layout.nodes}
          type="button"
          id={"map-node-#{node.id}"}
          data-mindmap-node
          phx-click="select_node"
          phx-value-id={node.id}
          style={
            "left:#{node.x - @layout.node_width / 2}px;top:#{node.y - @layout.node_height / 2}px;" <>
              "width:#{@layout.node_width}px;height:#{@layout.node_height}px"
          }
          class={[
            "group absolute flex items-center rounded-2xl border-2 bg-base-100 px-3 text-left",
            "transition duration-200 hover:z-10 hover:opacity-100 hover:shadow-md",
            node_surface(node, @ctx),
            selected_outline(node, @ctx),
            not AdaptiveStudy.node_enabled?(node.node) && "border-dashed",
            node_opacity(node, @ctx)
          ]}
        >
          <%!-- Badge da relação com o nó selecionado, pendurado na borda de cima
               para não roubar espaço do rótulo. --%>
          <span
            :if={@ctx.badges[node.id]}
            class={[
              "absolute -top-2.5 left-2 rounded-full border px-1.5 py-px text-[0.58rem] font-bold uppercase leading-tight",
              "bg-base-100",
              relation_badge_class(@ctx.badges[node.id])
            ]}
          >
            {badge_label(@ctx.badges[node.id])}
          </span>

          <%!-- Marca de onde você veio, para o retorno ser óbvio. --%>
          <span
            :if={node.id == @ctx.origin_id}
            class="absolute -top-2.5 right-2 inline-flex items-center gap-0.5 rounded-full border border-base-content/40 bg-base-100 px-1.5 py-px text-[0.58rem] font-bold uppercase leading-tight text-base-content/70"
          >
            <.icon name="hero-arrow-uturn-left" class="size-2.5" /> origem
          </span>

          <%!-- No radial há relações passando por baixo dos cartões, então lá quem
               esmaece é só o conteúdo e o fundo continua sólido. Na árvore nada
               passa por baixo e o cartão inteiro pode ficar quase transparente. --%>
          <span class={[
            "flex w-full items-center gap-2 transition-opacity duration-200 group-hover:opacity-100",
            content_opacity(node, @ctx)
          ]}>
            <span class={["size-2.5 shrink-0 rounded-full", priority_dot(node.node["priority"])]}></span>

            <span class="min-w-0 flex-1">
              <span class="line-clamp-2 text-xs font-semibold leading-tight">
                {node.node["label"] || "Sem rótulo"}
              </span>
            </span>

            <.icon name={type_icon(node.node)} class="size-3.5 shrink-0 opacity-40" />
          </span>
        </button>

        <%!-- Alternador de ramo. Fica fora do cartão de propósito, senão o clique
             de recolher borbulharia para o de selecionar — e na árvore ele ocupa
             exatamente a porta de saída, de onde os traços dos filhos partem. --%>
        <button
          :for={node <- toggle_nodes(@layout)}
          type="button"
          id={"map-toggle-#{node.id}"}
          phx-click="toggle_collapse"
          phx-value-id={node.id}
          title={if node.collapsed?, do: "Expandir ramo", else: "Recolher ramo"}
          style={toggle_position(@layout, node)}
          class={[
            "absolute z-10 grid size-[22px] place-items-center rounded-full border-2 border-base-300 text-[10px] font-bold shadow-sm",
            "transition duration-200 hover:scale-110 hover:opacity-100",
            if(node.collapsed?,
              do: "bg-primary text-primary-content",
              else: "bg-base-100 text-base-content/60"
            ),
            node_opacity(node, @ctx)
          ]}
        >
          {if node.collapsed?, do: node.children_count, else: "−"}
        </button>

        <%!-- Explorar: só aqui a vizinhança se move. O clique no cartão apenas
             abre os detalhes, para navegar não ser um efeito colateral de olhar. --%>
        <button
          :for={node <- explore_nodes(@layout)}
          type="button"
          id={"map-explore-#{node.id}"}
          phx-click="explore_node"
          phx-value-id={node.id}
          title={
            if node.id == @ctx.origin_id,
              do: "Voltar para este nó",
              else: "Explorar a vizinhança deste nó"
          }
          style={"left:#{node.x + @layout.node_width / 2 - 11}px;top:#{node.y - 11}px"}
          class={[
            "absolute z-10 grid size-[22px] place-items-center rounded-full border-2 shadow-sm",
            "transition duration-200 hover:scale-110",
            if(node.id == @ctx.origin_id,
              do: "border-base-content/40 bg-base-content/10 text-base-content",
              else:
                "border-base-300 bg-base-100 text-base-content/60 hover:border-primary hover:text-primary"
            )
          ]}
        >
          <.icon
            name={
              if node.id == @ctx.origin_id,
                do: "hero-arrow-uturn-left",
                else: "hero-arrow-right-circle"
            }
            class="size-3.5"
          />
        </button>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".MindmapPanZoom">
        const MIN_SCALE = 0.15;
        const MAX_SCALE = 2.5;

        export default {
          mounted() {
            this.scale = 1;
            this.tx = 0;
            this.ty = 0;
            this.dragging = false;
            this.lastDragEnd = 0;
            this.signature = this.el.dataset.signature;

            this.onWheel = (event) => {
              event.preventDefault();
              const rect = this.el.getBoundingClientRect();
              this.zoomAt(
                event.deltaY < 0 ? 1.12 : 1 / 1.12,
                event.clientX - rect.left,
                event.clientY - rect.top
              );
            };

            // Nada de setPointerCapture aqui: capturar o ponteiro faz o browser
            // reemitir o `click` no elemento que capturou, e não no botão do nó,
            // o que matava o phx-click="select_node". O arrasto é acompanhado
            // pela window, que também entrega o pointerup solto fora do canvas.
            this.onPointerDown = (event) => {
              if (event.button !== 0) return;
              this.origin = {x: event.clientX, y: event.clientY, tx: this.tx, ty: this.ty};
            };

            this.onPointerMove = (event) => {
              if (!this.origin) return;
              const dx = event.clientX - this.origin.x;
              const dy = event.clientY - this.origin.y;
              if (!this.dragging && Math.hypot(dx, dy) < 4) return;
              this.dragging = true;
              this.tx = this.origin.tx + dx;
              this.ty = this.origin.ty + dy;
              this.apply();
            };

            this.onPointerUp = () => {
              // Soltar depois de arrastar não pode virar seleção de nó. A janela
              // é temporal de propósito: uma flag booleana ficaria presa quando o
              // arrasto termina sem gerar clique.
              if (this.dragging) this.lastDragEnd = Date.now();
              this.dragging = false;
              this.origin = null;
            };

            this.onClickCapture = (event) => {
              if (Date.now() - this.lastDragEnd > 150) return;
              event.stopPropagation();
              event.preventDefault();
            };

            this.onFit = () => this.fit();
            this.onZoom = (event) => {
              const rect = this.el.getBoundingClientRect();
              this.zoomAt(event.detail?.factor || 1.2, rect.width / 2, rect.height / 2);
            };

            this.el.addEventListener("wheel", this.onWheel, {passive: false});
            this.el.addEventListener("pointerdown", this.onPointerDown);
            window.addEventListener("pointermove", this.onPointerMove);
            window.addEventListener("pointerup", this.onPointerUp);
            window.addEventListener("pointercancel", this.onPointerUp);
            this.el.addEventListener("click", this.onClickCapture, true);
            this.el.addEventListener("mindmap:fit", this.onFit);
            this.el.addEventListener("mindmap:zoom", this.onZoom);

            this.fit();
          },

          updated() {
            // O patch da LiveView remove o style aplicado por aqui: reaplicamos.
            const signature = this.el.dataset.signature;
            if (signature !== this.signature) {
              this.signature = signature;
              this.fit();
            } else {
              this.apply();
            }
          },

          destroyed() {
            this.el.removeEventListener("wheel", this.onWheel);
            this.el.removeEventListener("pointerdown", this.onPointerDown);
            window.removeEventListener("pointermove", this.onPointerMove);
            window.removeEventListener("pointerup", this.onPointerUp);
            window.removeEventListener("pointercancel", this.onPointerUp);
            this.el.removeEventListener("click", this.onClickCapture, true);
            this.el.removeEventListener("mindmap:fit", this.onFit);
            this.el.removeEventListener("mindmap:zoom", this.onZoom);
          },

          stage() {
            return this.el.querySelector("#mindmap-stage");
          },

          apply() {
            const stage = this.stage();
            if (stage) {
              stage.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`;
            }
          },

          fit() {
            const width = parseFloat(this.el.dataset.width) || 1;
            const height = parseFloat(this.el.dataset.height) || 1;
            const rect = this.el.getBoundingClientRect();
            if (!rect.width || !rect.height) return;

            this.scale = Math.max(
              MIN_SCALE,
              Math.min(rect.width / width, rect.height / height, 1)
            );
            this.tx = (rect.width - width * this.scale) / 2;
            this.ty = (rect.height - height * this.scale) / 2;
            this.apply();
          },

          zoomAt(factor, cx, cy) {
            const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale * factor));
            const ratio = next / this.scale;
            this.tx = cx - (cx - this.tx) * ratio;
            this.ty = cy - (cy - this.ty) * ratio;
            this.scale = next;
            this.apply();
          }
        }
      </script>
    </div>
    """
  end

  @doc "Legenda flutuante com o significado das cores e dos traços do canvas."
  attr :layout, :map, required: true

  def legend(assigns) do
    ~H"""
    <%!-- Escondida no mobile: lá a gaveta do nó já ocupa a largura toda. --%>
    <div class="pointer-events-none absolute bottom-3 left-3 hidden max-w-[22rem] rounded-2xl border border-base-300 bg-base-100/90 p-3 text-[0.65rem] shadow-sm backdrop-blur lg:block">
      <p class="mb-2 flex items-center gap-1.5 font-bold uppercase tracking-wider opacity-60">
        <.icon name="hero-map" class="size-3.5" /> Legenda
      </p>

      <div class="mb-2 flex flex-wrap items-center gap-x-3 gap-y-1">
        <span class="flex items-center gap-1.5">
          <span class="inline-block size-2 rounded-full bg-primary"></span> Alta
        </span>
        <span class="flex items-center gap-1.5">
          <span class="inline-block size-2 rounded-full bg-warning"></span> Média
        </span>
        <span class="flex items-center gap-1.5">
          <span class="inline-block size-2 rounded-full bg-base-300"></span> Baixa
        </span>
        <span class="flex items-center gap-1.5 opacity-60">
          <span class="inline-block h-0 w-4 border-t-2 border-dashed border-current"></span>
          relação transversal
        </span>
      </div>

      <div :if={@layout.relations != []} class="flex flex-wrap gap-x-3 gap-y-1">
        <span
          :for={type <- relation_types_present(@layout)}
          class={["flex items-center gap-1.5 font-semibold", relation_color(type)]}
        >
          <span class="inline-block h-0 w-4 border-t-2 border-dashed border-current"></span>
          {AdaptiveStudy.relation_label(type)}
        </span>
      </div>

      <p class="mt-2 opacity-50">
        Arraste para mover · scroll para zoom · clique no nó para abrir os detalhes
      </p>
    </div>
    """
  end

  defp relation_types_present(layout) do
    layout.relations |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()
  end

  # Rótulo longo em SVG não quebra linha: viraria uma faixa de texto atravessando
  # o mapa, então corta no que cabe sobre a curva.
  defp relation_text(%{label: label, type: type}) do
    case String.trim(to_string(label || "")) do
      "" -> AdaptiveStudy.relation_label(type)
      text when byte_size(text) > 32 -> String.slice(text, 0, 29) <> "…"
      text -> text
    end
  end

  defp relation_badge_class(:parent), do: "border-base-content/30 text-base-content/70"
  defp relation_badge_class(:child), do: "border-base-content/30 text-base-content/70"
  defp relation_badge_class("prerequisito"), do: "border-warning text-warning"
  defp relation_badge_class("aprofunda"), do: "border-primary text-primary"
  defp relation_badge_class("contrasta"), do: "border-error text-error"
  defp relation_badge_class("exemplifica"), do: "border-success text-success"
  defp relation_badge_class("aplica"), do: "border-info text-info"
  defp relation_badge_class(_), do: "border-secondary text-secondary"

  defp relation_surface_class("prerequisito"),
    do: "border-warning shadow-md ring-1 ring-warning/30"

  defp relation_surface_class("aprofunda"), do: "border-primary shadow-md ring-1 ring-primary/30"
  defp relation_surface_class("contrasta"), do: "border-error shadow-md ring-1 ring-error/30"

  defp relation_surface_class("exemplifica"),
    do: "border-success shadow-md ring-1 ring-success/30"

  defp relation_surface_class("aplica"), do: "border-info shadow-md ring-1 ring-info/30"
  defp relation_surface_class(_), do: "border-secondary shadow-md ring-1 ring-secondary/30"

  defp relation_color("prerequisito"), do: "text-warning"
  defp relation_color("aprofunda"), do: "text-primary"
  defp relation_color("contrasta"), do: "text-error"
  defp relation_color("exemplifica"), do: "text-success"
  defp relation_color("aplica"), do: "text-info"
  defp relation_color(_), do: "text-secondary"

  # Na árvore, relação transversal é ruído até você pedir por ela: sem seleção o
  # canvas mostra só a formação da árvore. No radial, a teia é o próprio produto.
  defp visible_relations(%{mode: :tree}, nil), do: []

  defp visible_relations(%{mode: :tree} = layout, selected_id) do
    Enum.filter(layout.relations, &(&1.from_id == selected_id or &1.to_id == selected_id))
  end

  defp visible_relations(layout, _selected_id), do: layout.relations

  # Tudo que decide a aparência de um nó em um lugar só, montado uma vez por
  # render em vez de recalculado por cartão.
  defp context(assigns) do
    layout = assigns.layout
    anchor = badge_anchor(layout, assigns.selected_id)

    %{
      mode: layout.mode,
      selected_id: assigns.selected_id,
      origin_id: assigns.origin_id,
      anchor_id: anchor,
      badges: badges_for(layout, anchor)
    }
  end

  # No foco as ligações partem todas do centro, que pode não ser o nó aberto na
  # gaveta: as etiquetas descrevem a conexão com o centro.
  defp badge_anchor(%{mode: :focus} = layout, _selected_id) do
    case Enum.find(layout.nodes, &(&1.depth == 0)) do
      nil -> nil
      center -> center.id
    end
  end

  defp badge_anchor(_layout, selected_id), do: selected_id

  # No foco os subnós já aparecem no leque da direita; recolher ramo não faz
  # sentido ali.
  defp toggle_nodes(%{mode: :focus}), do: []
  defp toggle_nodes(layout), do: Enum.filter(layout.nodes, &(&1.children_count > 0))

  # Explorar só existe no foco, e não no próprio centro — ele já é o centro.
  defp explore_nodes(%{mode: :focus} = layout), do: Enum.filter(layout.nodes, &(&1.depth > 0))
  defp explore_nodes(_layout), do: []

  # Na vizinhança, os vizinhos de hierarquia também ganham etiqueta — senão o
  # pai e os subnós ficariam indistinguíveis dos parceiros de relação.
  defp badges_for(%{mode: :focus} = layout, anchor_id) do
    hierarchy =
      layout.edges
      |> Enum.flat_map(fn edge ->
        cond do
          edge.from_id == anchor_id -> [{edge.to_id, :child}]
          edge.to_id == anchor_id -> [{edge.from_id, :parent}]
          true -> []
        end
      end)
      |> Map.new()

    Map.merge(relation_badges(layout, anchor_id), hierarchy)
  end

  defp badges_for(layout, anchor_id), do: relation_badges(layout, anchor_id)

  defp badge_label(:parent), do: "nó pai"
  defp badge_label(:child), do: "subnó"
  defp badge_label(type), do: AdaptiveStudy.relation_label(type)

  # %{id_do_nó_relacionado => tipo_da_relação} para o nó âncora.
  defp relation_badges(_layout, nil), do: %{}

  defp relation_badges(layout, anchor_id) do
    layout.relations
    |> Enum.flat_map(fn relation ->
      cond do
        relation.from_id == anchor_id -> [{relation.to_id, relation.type}]
        relation.to_id == anchor_id -> [{relation.from_id, relation.type}]
        true -> []
      end
    end)
    |> Map.new()
  end

  # Realce da seleção: na árvore, o nó escolhido e os relacionados a ele ficam
  # cheios e o resto cai para 20%. No foco tudo que está em cena é relevante, e
  # no radial quem esmaece é só o conteúdo (linhas passam por baixo dos cartões).
  # Uma única classe de opacidade por elemento — duas utilitárias de opacidade no
  # mesmo `class` brigariam pela ordem do CSS, não pela ordem escrita aqui.
  defp node_opacity(node, %{mode: :tree} = ctx) do
    if node_state(node, ctx) == :muted, do: "opacity-20", else: "opacity-100"
  end

  defp node_opacity(_node, _ctx), do: "opacity-100"

  defp content_opacity(node, %{mode: mode}) when mode in [:tree, :focus] do
    if AdaptiveStudy.node_enabled?(node.node), do: "opacity-100", else: "opacity-30"
  end

  defp content_opacity(node, ctx) do
    cond do
      not AdaptiveStudy.node_enabled?(node.node) -> "opacity-20"
      is_nil(ctx.selected_id) -> "opacity-100"
      node.id == ctx.selected_id -> "opacity-100"
      true -> "opacity-30"
    end
  end

  defp node_state(node, %{mode: :focus} = ctx) do
    cond do
      node.depth == 0 -> :center
      node.id == ctx.origin_id -> :origin
      is_map_key(ctx.badges, node.id) -> :related
      true -> :normal
    end
  end

  defp node_state(node, ctx) do
    cond do
      is_nil(ctx.selected_id) -> :normal
      node.id == ctx.selected_id -> :selected
      is_map_key(ctx.badges, node.id) -> :related
      true -> :muted
    end
  end

  # No foco tudo em cena liga ao centro, então nada esmaece.
  defp edge_opacity(_edge, %{mode: :focus}), do: "opacity-100"
  defp edge_opacity(_edge, %{selected_id: nil}), do: "opacity-100"

  defp edge_opacity(edge, ctx) do
    if edge.from_id == ctx.selected_id or edge.to_id == ctx.selected_id,
      do: "opacity-100",
      else: "opacity-20"
  end

  # Na árvore o alternador ocupa a porta de saída, no meio da borda de trás; no
  # radial não há "trás", então ele fica no canto.
  defp toggle_position(%{mode: :tree} = layout, node) do
    "left:#{node.x + layout.node_width / 2 - 11}px;top:#{node.y - 11}px"
  end

  defp toggle_position(layout, node) do
    "left:#{node.x + layout.node_width / 2 - 11}px;top:#{node.y + layout.node_height / 2 - 11}px"
  end

  # Sem preenchimento translúcido no destacado (`bg-primary/10` substituiria o
  # `bg-base-100`): o destaque vem de borda, anel e sombra. Quem recua perde a
  # sombra — é ela que faz a caixa "flutuar" e chamar atenção.
  defp node_surface(node, ctx) do
    case node_state(node, ctx) do
      :center -> "border-primary shadow-lg ring-2 ring-primary/40"
      :selected -> "border-primary shadow-lg ring-2 ring-primary/40"
      # Neutro forte de propósito: "de onde vim" não é uma relação semântica e
      # não pode disputar cor com os tipos de relação.
      :origin -> "border-base-content/50 shadow-md ring-2 ring-base-content/20"
      :related -> relation_surface_class(ctx.badges[node.id])
      :muted -> "border-base-300/50"
      :normal when node.depth == 0 -> "border-primary/60 shadow-sm"
      :normal -> "border-base-300 shadow-sm hover:border-primary/50"
    end
  end

  # No foco o cartão aberto na gaveta pode não ser o centro, e clicar precisa dar
  # retorno visual. Vai de `outline` e não de `ring` porque os relacionados já
  # usam `ring` para a cor do tipo de relação — dois anéis brigariam.
  defp selected_outline(node, %{mode: :focus} = ctx) do
    if node.id == ctx.selected_id and node.depth > 0,
      do: "outline outline-2 outline-offset-2 outline-primary/50"
  end

  defp selected_outline(_node, _ctx), do: nil

  defp priority_dot("high"), do: "bg-primary"
  defp priority_dot("low"), do: "bg-base-300"
  defp priority_dot(_), do: "bg-warning"

  defp type_icon(node) do
    case AdaptiveStudy.node_type(node) do
      "definicao" -> "hero-book-open"
      "processo" -> "hero-cog-6-tooth"
      "exemplo" -> "hero-beaker"
      "dado" -> "hero-chart-bar"
      "advertencia" -> "hero-exclamation-triangle"
      _ -> "hero-light-bulb"
    end
  end
end
