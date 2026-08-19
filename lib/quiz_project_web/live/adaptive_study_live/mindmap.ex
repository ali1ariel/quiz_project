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

  # Lado do botão de explorar, em pixels. O valor entra no cálculo da posição
  # (o botão é centrado na porta de saída do cartão) e precisa casar com a
  # classe `size-[32px]` do próprio botão — o Tailwind só enxerga classe
  # literal, então a medida não pode ser interpolada lá.
  @explore_size 32

  attr :layout, :map, required: true
  attr :selected_id, :string, default: nil
  attr :origin_id, :string, default: nil

  attr :entry_id, :string,
    default: nil,
    doc: "nó em que a visão se abre quando o mapa não cabe inteiro na tela"

  def canvas(assigns) do
    # Na árvore as relações transversais só entram em cena quando um nó é
    # selecionado: por padrão a tela mostra a formação da árvore e nada mais.
    entry = Enum.find(assigns.layout.nodes, &(&1.id == assigns.entry_id))

    assigns =
      assign(assigns,
        relations: visible_relations(assigns.layout, assigns.selected_id),
        ctx: context(assigns),
        entry: entry,
        # Dentro do ~H, `@x` é `assigns.x`: o atributo de módulo precisa vir
        # por aqui para o cálculo da posição enxergá-lo.
        explore_size: @explore_size
      )

    ~H"""
    <div
      id="mindmap-canvas"
      phx-hook=".MindmapPanZoom"
      data-width={@layout.width}
      data-height={@layout.height}
      data-entry-x={@entry && @entry.x}
      data-entry-y={@entry && @entry.y}
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
          class={
            [
              "group absolute flex items-center rounded-2xl border-2 px-3 text-left",
              "transition duration-200 hover:z-10 hover:opacity-100 hover:shadow-md",
              node_surface(node, @ctx),
              selected_outline(node, @ctx),
              not AdaptiveStudy.node_enabled?(node.node) && "border-dashed",
              node_opacity(node, @ctx),
              # Fundo recuado: sinaliza atalho em vez de peça do desenho, sem usar
              # borda tracejada — ali tracejado já quer dizer "nó inativo".
              if(detached?(node), do: "bg-base-200", else: "bg-base-100")
            ]
          }
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

          <%!-- Âncora de volta: a raiz trazida para a cena sem fazer parte do
               desenho. O rótulo é o que evita ler o cartão sem ligação como um
               nó órfão do mapa. --%>
          <span
            :if={detached?(node)}
            class="absolute -top-2.5 left-2 inline-flex items-center gap-0.5 rounded-full border border-primary/40 bg-base-100 px-1.5 py-px text-[0.58rem] font-bold uppercase leading-tight text-primary"
          >
            <.icon name="hero-home" class="size-2.5" /> raiz
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
            <%!-- Prioridade e tipo na mesma marca: a bola dá a cor da prioridade
                 e o ícone dentro dela diz o tipo. Antes eram dois símbolos em
                 pontas opostas do cartão, e o da direita disputava espaço com o
                 rótulo — que é o que de fato se lê. --%>
            <span
              class={[
                "grid size-5 shrink-0 place-items-center rounded-full",
                priority_dot(node.node["priority"])
              ]}
              title={
                "#{priority_label(node.node["priority"])} · #{AdaptiveStudy.node_type_label(AdaptiveStudy.node_type(node.node))}"
              }
            >
              <.icon name={type_icon(AdaptiveStudy.node_type(node.node))} class="size-3" />
            </span>

            <span class="min-w-0 flex-1">
              <span class="line-clamp-2 text-xs font-semibold leading-tight">
                {node.node["label"] || "Sem rótulo"}
              </span>
            </span>
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
          style={"left:#{node.x + @layout.node_width / 2 - @explore_size / 2}px;top:#{node.y - @explore_size / 2}px"}
          class={[
            "absolute z-10 grid size-[32px] place-items-center rounded-full border-2 shadow-sm",
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
            class="size-4"
          />
        </button>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".MindmapPanZoom">
        const MIN_SCALE = 0.15;
        const MAX_SCALE = 2.0;
        // Piso de legibilidade da abertura. Enquadrar um mapa de centenas de nós
        // cabia tudo na tela a ~0.2 de escala, onde nenhum rótulo se lê. Ao abrir
        // preferimos escala legível e mostrar um pedaço; o botão de enquadrar
        // continua dando a visão geral, aí sim sem piso.
        const MIN_READABLE = 0.6;

        export default {
          mounted() {
            this.scale = 1;
            this.tx = 0;
            this.ty = 0;
            this.dragging = false;
            this.lastDragEnd = 0;
            this.signature = this.el.dataset.signature;
            this.pointers = new Map();
            this.pinch = null;

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
            // Um dedo arrasta (como antes); dois dedos fazem pinça — a escala
            // muda pela razão de distância entre os dois toques, e o ponto médio
            // entre eles serve de âncora do zoom, o mesmo papel que o cursor tem
            // em `onWheel`.
            //
            // A baseline (origem do arrasto, ou distância e ponto médio da
            // pinça) é recalculada a cada mudança na contagem de ponteiros, não
            // só no primeiro toque: sem isto, tirar ou pousar um dedo no meio do
            // gesto faz o mapa saltar, porque a fórmula incremental partiria de
            // um estado que não existe mais.
            this.onPointerDown = (event) => {
              if (event.button !== 0) return;
              this.pointers.set(event.pointerId, {x: event.clientX, y: event.clientY});
              this.beginGesture();
            };

            this.onPointerMove = (event) => {
              if (!this.pointers.has(event.pointerId)) return;
              this.pointers.set(event.pointerId, {x: event.clientX, y: event.clientY});

              if (this.pointers.size >= 2) {
                this.updatePinch();
                return;
              }

              if (!this.origin) return;
              const dx = event.clientX - this.origin.x;
              const dy = event.clientY - this.origin.y;
              if (!this.dragging && Math.hypot(dx, dy) < 4) return;
              this.dragging = true;
              this.tx = this.origin.tx + dx;
              this.ty = this.origin.ty + dy;
              this.apply();
            };

            this.onPointerUp = (event) => {
              this.pointers.delete(event.pointerId);
              // Soltar depois de arrastar ou beliscar não pode virar seleção de
              // nó. A janela é temporal de propósito: uma flag booleana ficaria
              // presa quando o gesto termina sem gerar clique.
              if (this.dragging || this.pinch) this.lastDragEnd = Date.now();
              this.dragging = false;
              this.beginGesture();
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

            // `dblclick` já é o evento que o browser sintetiza tanto para
            // duplo-clique de mouse quanto para toque duplo — reaproveitar
            // evita reimplementar a janela de tempo entre toques.
            //
            // Quando este clique for esbarrar no teto do zoom, ele mesmo já
            // volta ao enquadramento inicial em vez de só grudar no limite —
            // checar depois de aplicado deixaria um clique "parado" no teto,
            // sem mudança visível, antes do próximo finalmente resetar.
            this.onDblClick = (event) => {
              event.preventDefault();
              if (this.scale * 1.6 >= MAX_SCALE - 1e-6) {
                this.frame(true);
                return;
              }
              const rect = this.el.getBoundingClientRect();
              this.zoomAt(1.6, event.clientX - rect.left, event.clientY - rect.top);
            };

            this.el.addEventListener("wheel", this.onWheel, {passive: false});
            this.el.addEventListener("pointerdown", this.onPointerDown);
            window.addEventListener("pointermove", this.onPointerMove);
            window.addEventListener("pointerup", this.onPointerUp);
            window.addEventListener("pointercancel", this.onPointerUp);
            this.el.addEventListener("click", this.onClickCapture, true);
            this.el.addEventListener("dblclick", this.onDblClick);
            this.el.addEventListener("mindmap:fit", this.onFit);
            this.el.addEventListener("mindmap:zoom", this.onZoom);

            this.frame(true);
          },

          updated() {
            // O patch da LiveView remove o style aplicado por aqui: reaplicamos.
            const signature = this.el.dataset.signature;
            if (signature !== this.signature) {
              this.signature = signature;
              this.frame(true);
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
            this.el.removeEventListener("dblclick", this.onDblClick);
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

          // `readable` distingue as duas intenções: abrir o mapa (respeita o piso
          // de legibilidade e centraliza no nó de entrada) e enquadrar sob
          // demanda (cabe tudo, custe o tamanho que custar).
          frame(readable) {
            const width = parseFloat(this.el.dataset.width) || 1;
            const height = parseFloat(this.el.dataset.height) || 1;
            const rect = this.el.getBoundingClientRect();
            if (!rect.width || !rect.height) return;

            const fitScale = Math.min(rect.width / width, rect.height / height, 1);
            this.scale = readable
              ? Math.max(fitScale, MIN_READABLE)
              : Math.max(MIN_SCALE, fitScale);

            const scaledWidth = width * this.scale;
            const scaledHeight = height * this.scale;
            const entryX = parseFloat(this.el.dataset.entryX);
            const entryY = parseFloat(this.el.dataset.entryY);

            // Eixo a eixo: sobrando espaço, centraliza o mapa; faltando, mira o
            // nó de entrada e limita para não abrir em cima do vazio de fora.
            // O limite é o que faz a árvore abrir pelo topo (a raiz fica na borda
            // superior) e a rede abrir pelo meio, sem regra especial por modo.
            const place = (viewport, scaled, entry) => {
              if (scaled <= viewport) return (viewport - scaled) / 2;
              if (!Number.isFinite(entry)) return (viewport - scaled) / 2;
              return Math.min(0, Math.max(viewport - scaled, viewport / 2 - entry * this.scale));
            };

            this.tx = place(rect.width, scaledWidth, entryX);
            this.ty = place(rect.height, scaledHeight, entryY);
            this.apply();
          },

          fit() {
            this.frame(false);
          },

          zoomAt(factor, cx, cy) {
            const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale * factor));
            const ratio = next / this.scale;
            this.tx = cx - (cx - this.tx) * ratio;
            this.ty = cy - (cy - this.ty) * ratio;
            this.scale = next;
            this.apply();
          },

          beginGesture() {
            const points = [...this.pointers.values()];

            if (points.length === 1) {
              this.origin = {x: points[0].x, y: points[0].y, tx: this.tx, ty: this.ty};
              this.pinch = null;
            } else if (points.length >= 2) {
              const [p1, p2] = points;
              const rect = this.el.getBoundingClientRect();
              this.pinch = {
                dist: Math.hypot(p2.x - p1.x, p2.y - p1.y),
                midX: (p1.x + p2.x) / 2 - rect.left,
                midY: (p1.y + p2.y) / 2 - rect.top
              };
              this.origin = null;
            } else {
              this.origin = null;
              this.pinch = null;
            }
          },

          updatePinch() {
            const [p1, p2] = [...this.pointers.values()];
            const rect = this.el.getBoundingClientRect();
            const dist = Math.hypot(p2.x - p1.x, p2.y - p1.y);
            const midX = (p1.x + p2.x) / 2 - rect.left;
            const midY = (p1.y + p2.y) / 2 - rect.top;

            // O ponto médio se desloca por dois motivos ao mesmo tempo — os dois
            // dedos arrastando juntos, e a própria pinça abrindo ou fechando —
            // então primeiro acompanha esse deslocamento (pan) e só depois
            // aplica o zoom ancorado no ponto já reposicionado.
            this.tx += midX - this.pinch.midX;
            this.ty += midY - this.pinch.midY;
            this.zoomAt(dist / this.pinch.dist, midX, midY);

            this.pinch = {dist, midX, midY};
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
    <%!-- Aparece a partir de `md` (768px), que é onde ela e a gaveta cabem lado
         a lado: 22rem da legenda + 24rem da gaveta + margens dão 760px. Em 640px
         a gaveta passaria por cima dela, e no telefone a gaveta é folha de baixo
         e ocupa justamente este canto. --%>
    <div
      id="mindmap-legend"
      class="pointer-events-none absolute bottom-3 left-3 hidden max-w-[22rem] rounded-2xl border border-base-300 bg-base-100/90 p-3 text-[0.65rem] shadow-sm backdrop-blur md:block"
    >
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

      <%!-- O ícone dentro da bola do cartão. A amostra repete o formato de lá
           (círculo com o símbolo dentro) para a associação ser imediata; a cor
           fica neutra porque quem a define é a prioridade, logo acima. --%>
      <div class="mt-2 flex flex-wrap gap-x-3 gap-y-1 border-t border-base-300 pt-2">
        <span :for={type <- node_types_present(@layout)} class="flex items-center gap-1.5">
          <span class="grid size-4 shrink-0 place-items-center rounded-full bg-base-300 text-base-content/70">
            <.icon name={type_icon(type)} class="size-2.5" />
          </span>
          {AdaptiveStudy.node_type_label(type)}
        </span>
      </div>

      <%!-- Os dois botões redondos que ficam soltos sobre o mapa. --%>
      <div class="mt-2 flex flex-wrap gap-x-3 gap-y-1 border-t border-base-300 pt-2">
        <span class="flex items-center gap-1.5">
          <span class="grid size-4 shrink-0 place-items-center rounded-full border-2 border-base-300 text-[9px] font-bold leading-none">
            −
          </span>
          recolher ramo (o número mostra quantos nós ficam ocultos)
        </span>
        <span class="flex items-center gap-1.5">
          <span class="grid size-4 shrink-0 place-items-center rounded-full border-2 border-base-300">
            <.icon name="hero-arrow-right-circle" class="size-2.5" />
          </span>
          explorar a vizinhança deste nó
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
  # Nós de árvore e rede não têm a chave: só o foco monta a âncora de volta.
  defp detached?(node), do: Map.get(node, :detached?, false)

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

  # A cor do texto acompanha a do fundo: agora que a bola carrega um ícone
  # dentro, herdar a cor do cartão deixaria o símbolo ilegível sobre o cheio.
  defp priority_dot("high"), do: "bg-primary text-primary-content"
  defp priority_dot("low"), do: "bg-base-300 text-base-content/70"
  defp priority_dot(_), do: "bg-warning text-warning-content"

  defp priority_label("high"), do: "Prioridade alta"
  defp priority_label("low"), do: "Prioridade baixa"
  defp priority_label(_), do: "Prioridade média"

  defp type_icon("definicao"), do: "hero-book-open"
  defp type_icon("processo"), do: "hero-cog-6-tooth"
  defp type_icon("exemplo"), do: "hero-beaker"
  defp type_icon("dado"), do: "hero-chart-bar"
  defp type_icon("advertencia"), do: "hero-exclamation-triangle"
  defp type_icon(_), do: "hero-light-bulb"

  # Só os tipos que aparecem no mapa, na ordem canônica do domínio: listar os
  # seis sempre encheria a legenda de símbolo que não está em cena.
  defp node_types_present(layout) do
    present = MapSet.new(layout.nodes, &AdaptiveStudy.node_type(&1.node))
    Enum.filter(AdaptiveStudy.node_types(), &MapSet.member?(present, &1))
  end
end
