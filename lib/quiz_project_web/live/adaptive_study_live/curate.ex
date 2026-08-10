defmodule QuizProjectWeb.AdaptiveStudyLive.Curate do
  use QuizProjectWeb, :live_view

  import QuizProjectWeb.Components.Markdown, only: [markdown: 1]

  alias Phoenix.LiveView.JS
  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.AdaptiveStudy.MindmapLayout
  alias QuizProjectWeb.AdaptiveStudyLive.Mindmap

  # Campos que o formulário de edição do nó controla. `user_notes` fica de fora
  # de propósito: ele tem formulário próprio e era zerado a cada edição de nó.
  @editable_fields ~w(label content priority priority_reason complexity complexity_reason)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case AdaptiveStudy.get_material(id, user) do
      {:ok, material} ->
        # Também na leitura, e não só ao gerar: materiais processados antes desta
        # normalização continuariam sem centro. Como a função é idempotente, o
        # que já tem raiz passa direto, e a raiz criada aqui é gravada no próximo
        # salvamento da curadoria.
        nodes =
          material.mindmap_tree
          |> get_in(["nodes"])
          |> Kernel.||([])
          |> AdaptiveStudy.ensure_root(material.title)

        first = List.first(AdaptiveStudy.flatten_nodes(nodes))

        {:ok,
         socket
         |> assign(
           page_title: "Curadoria: " <> material.title,
           material: material,
           book_material_id: book_material_id(material.id),
           map_mode: :tree,
           focus_center_id: nil,
           focus_origin_id: nil,
           collapsed_ids: MindmapLayout.initial_collapsed(nodes),
           editing_node?: false,
           dirty?: false,
           show_reconstruction_modal?: false,
           # No telefone o detalhamento é um modal, e o nó pré-selecionado abaixo
           # abriria esse modal por cima do sumário já na carga da página. O modal
           # só sobe depois de um clique; a coluna do desktop, essa sim, já nasce
           # preenchida.
           node_modal_open?: false
         )
         |> assign_tree(nodes, selected_node_id: first && first["id"])}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Material de estudo não encontrado.")
         |> push_navigate(to: ~p"/adaptive-study")}
    end
  end

  # O layout do mapa só existe no modo imersivo; `handle_params` cobre tanto a
  # entrada por URL direta quanto o patch vindo da tela de curadoria.
  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      if socket.assigns.live_action == :map do
        # O mapa abre limpo: sem nó selecionado, a árvore aparece inteira, sem
        # realce, sem relações transversais e sem gaveta por cima.
        assign(socket,
          selected_node_id: nil,
          selected_node: nil,
          editing_node?: false,
          node_modal_open?: false,
          focus_center_id: nil,
          focus_origin_id: nil
        )
      else
        socket
      end

    {:noreply, assign_map_layout(socket)}
  end

  @impl true
  def handle_event("switch_map_mode", %{"mode" => mode}, socket) do
    new_mode =
      case mode do
        "radial" -> :radial
        "focus" -> :focus
        _ -> :tree
      end

    socket =
      if new_mode == :focus do
        # Entrar no foco centraliza no nó selecionado — ou na raiz, quando ainda
        # não há seleção, para o modo estar disponível desde o início.
        assign(socket,
          focus_center_id: socket.assigns.selected_node_id || root_node_id(socket.assigns.nodes),
          focus_origin_id: nil
        )
      else
        socket
      end

    {:noreply, socket |> assign(map_mode: new_mode) |> assign_map_layout()}
  end

  @impl true
  def handle_event("focus_root", _params, socket) do
    # Retorno direto: limpa a origem porque voltar à raiz é recomeçar a
    # navegação, não mais um salto com trilha de volta.
    {:noreply,
     socket
     |> assign(
       map_mode: :focus,
       focus_center_id: root_node_id(socket.assigns.nodes),
       focus_origin_id: nil
     )
     |> assign_map_layout()}
  end

  @impl true
  def handle_event("explore_node", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(
       map_mode: :focus,
       focus_center_id: id,
       # Guarda de onde veio para o cartão de retorno ficar marcado no novo mapa.
       focus_origin_id: socket.assigns.focus_center_id
     )
     |> assign_map_layout()}
  end

  @impl true
  def handle_event("toggle_collapse", %{"id" => id}, socket) do
    collapsed = socket.assigns.collapsed_ids

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    {:noreply, socket |> assign(collapsed_ids: collapsed) |> assign_map_layout()}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    {:noreply, socket |> assign(collapsed_ids: MapSet.new()) |> assign_map_layout()}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    # A raiz fica de fora (profundidade mínima 1): recolhê-la apagaria o mapa,
    # já que o nó recolhido some do desenho. O botão só existe no mapa imersivo.
    collapsed = MapSet.new(MindmapLayout.branch_ids(socket.assigns.nodes, 1))

    {:noreply, socket |> assign(collapsed_ids: collapsed) |> assign_map_layout()}
  end

  @impl true
  def handle_event("select_node", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.flattened_nodes, &(&1["id"] == id))

    {:noreply,
     socket
     |> assign(
       selected_node_id: id,
       selected_node: node,
       editing_node?: false,
       node_modal_open?: true
     )
     |> assign_map_layout()}
  end

  @impl true
  def handle_event("close_node_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(
       selected_node_id: nil,
       selected_node: nil,
       editing_node?: false,
       node_modal_open?: false
     )
     |> assign_map_layout()}
  end

  @impl true
  def handle_event("toggle_edit_node", _params, socket) do
    {:noreply, assign(socket, editing_node?: !socket.assigns.editing_node?)}
  end

  @impl true
  def handle_event("toggle_node_enabled", %{"id" => id}, socket) do
    nodes =
      update_node_in_tree(socket.assigns.nodes, id, fn node ->
        Map.put(node, "enabled", not AdaptiveStudy.node_enabled?(node))
      end)

    {:noreply, socket |> assign_tree(nodes) |> mark_dirty()}
  end

  @impl true
  def handle_event("update_node", params, socket) do
    changes =
      Enum.reduce(@editable_fields, %{}, fn field, acc ->
        case Map.fetch(params, field) do
          {:ok, value} when is_binary(value) -> Map.put(acc, field, value)
          _ -> acc
        end
      end)

    nodes =
      update_node_in_tree(socket.assigns.nodes, socket.assigns.selected_node_id, fn node ->
        Map.merge(node, changes)
      end)

    {:noreply,
     socket
     |> assign_tree(nodes)
     |> assign(editing_node?: false)
     |> mark_dirty()
     |> put_flash(:info, "Nó atualizado. Salve a curadoria para gravar as alterações.")}
  end

  @impl true
  def handle_event("save_user_notes", %{"user_notes" => notes}, socket) do
    nodes =
      update_node_in_tree(socket.assigns.nodes, socket.assigns.selected_node_id, fn node ->
        Map.put(node, "user_notes", notes)
      end)

    {:noreply,
     socket
     |> assign_tree(nodes)
     |> mark_dirty()
     |> put_flash(:info, "Anotação registrada. Salve a curadoria para gravar as alterações.")}
  end

  @impl true
  def handle_event("remove_cross_reference", %{"target_id" => target_id}, socket) do
    nodes =
      update_node_in_tree(
        socket.assigns.nodes,
        socket.assigns.selected_node_id,
        &drop_relation(&1, target_id)
      )

    {:noreply, socket |> assign_tree(nodes) |> mark_dirty()}
  end

  @impl true
  def handle_event("save_curation", _params, socket) do
    user = socket.assigns.current_user
    material = socket.assigns.material

    case AdaptiveStudy.update_material(
           material,
           %{
             mindmap_tree: %{"nodes" => socket.assigns.nodes},
             status: "curated"
           },
           user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(material: updated, dirty?: false)
         |> put_flash(:info, "Curadoria do Mapa Mental salva com sucesso!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Erro ao salvar curadoria.")}
    end
  end

  @impl true
  def handle_event("toggle_reconstruction_modal", _params, socket) do
    {:noreply,
     assign(socket, show_reconstruction_modal?: !socket.assigns.show_reconstruction_modal?)}
  end

  @impl true
  def handle_event("close_reconstruction_modal", _params, socket) do
    {:noreply, assign(socket, show_reconstruction_modal?: false)}
  end

  # O usuário autenticado assina "user:<id>:attempts" no on_mount, então esta
  # LiveView recebe as mensagens de tentativas e de mapas mentais. Sem estas
  # cláusulas a página derrubava com FunctionClauseError ao receber qualquer uma.
  @impl true
  def handle_info({:mindmap_generated, %{material_id: material_id}}, socket) do
    material = socket.assigns.material

    # Só recarrega quando a árvore ainda está vazia: caso contrário sobrescreveria
    # a curadoria em andamento.
    if material_id == material.id and socket.assigns.nodes == [] do
      case AdaptiveStudy.get_material(material_id, socket.assigns.current_user) do
        {:ok, reloaded} ->
          nodes =
            reloaded.mindmap_tree
            |> get_in(["nodes"])
            |> Kernel.||([])
            |> AdaptiveStudy.ensure_root(reloaded.title)

          first = List.first(AdaptiveStudy.flatten_nodes(nodes))

          {:noreply,
           socket
           |> assign(
             material: reloaded,
             page_title: "Curadoria: " <> reloaded.title,
             book_material_id: book_material_id(reloaded.id),
             collapsed_ids: MindmapLayout.initial_collapsed(nodes)
           )
           |> assign_tree(nodes, selected_node_id: first && first["id"])
           |> put_flash(:info, "Mapa Mental pronto! Você já pode iniciar a curadoria.")}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # `nil` para material de upload manual ou de material antigo já com `content`
  # gravado; o id do material do LIVRO quando este material de texto veio de
  # curadoria de capítulo — é o que `node_text/2` usa para decidir se resolve o
  # trecho do nó a partir dos blocos.
  defp book_material_id(material_id) do
    case Books.chapter_for_curated_material(material_id) do
      {:ok, %{material_id: book_id}} -> book_id
      _ -> nil
    end
  end

  # `content` continua valendo quando presente — materiais já curados antes
  # desta mudança, e o upload manual de texto (que não tem blocos), gravam o
  # trecho ali. Só quando o nó veio vazio de um material de livro é que o
  # texto é resolvido a partir dos blocos que a curadoria demarcou.
  defp node_text(node, book_material_id) do
    case node["content"] do
      content when is_binary(content) and content != "" ->
        content

      _ ->
        resolve_from_blocks(node["id"], book_material_id)
    end
  end

  defp resolve_from_blocks(_node_id, nil), do: ""

  defp resolve_from_blocks(node_id, book_material_id) do
    book_material_id
    |> Books.blocks_for_node(node_id)
    |> Enum.map_join("\n\n", &block_markdown(&1, book_material_id))
  end

  # Bloco `:figure` guarda a legenda em `content` e a imagem à parte, em
  # `image_path` — juntar só o `content` (como os outros tipos) mostraria a
  # legenda sem a imagem. Em markdown a imagem entra pela mesma URL que o
  # leitor usa (`BookImageController`), e a legenda repete embaixo, como o
  # `<figcaption>` do leitor.
  defp block_markdown(%{type: :figure, image_path: nil, content: caption}, _book_material_id),
    do: caption || ""

  defp block_markdown(%{type: :figure, image_path: path, content: caption}, book_material_id) do
    legenda = caption || ""

    "![#{legenda}](#{image_url(book_material_id, path)})" <>
      if(legenda != "", do: "\n\n#{legenda}", else: "")
  end

  defp block_markdown(%{content: content}, _book_material_id), do: content

  defp image_url(material_id, path), do: "/contents/#{material_id}/images/#{path}"

  # Recalcula tudo que deriva da árvore em um só lugar (antes cada handler
  # repetia — e esquecia — parte dos assigns derivados).
  defp assign_tree(socket, nodes, opts \\ []) do
    flattened = AdaptiveStudy.flatten_nodes(nodes)
    selected_id = Keyword.get(opts, :selected_node_id, socket.assigns[:selected_node_id])

    socket
    |> assign(
      nodes: nodes,
      flattened_nodes: flattened,
      selected_node_id: selected_id,
      selected_node: Enum.find(flattened, &(&1["id"] == selected_id)),
      stats: node_stats(flattened),
      reconstructed_text: AdaptiveStudy.reconstruct_raw_text(nodes)
    )
    |> assign_map_layout()
  end

  # O cálculo do layout só vale a pena no modo imersivo; fora dele o assign fica
  # nulo para não recalcular posições a cada edição de nó.
  defp assign_map_layout(socket) do
    if socket.assigns[:live_action] == :map do
      assign(socket, :map_layout, map_layout(socket.assigns))
    else
      assign(socket, :map_layout, nil)
    end
  end

  defp map_layout(%{map_mode: :focus} = assigns) do
    MindmapLayout.focus(assigns.nodes, focus_center(assigns))
  end

  defp map_layout(assigns) do
    MindmapLayout.build(assigns.nodes, assigns.map_mode, assigns.collapsed_ids)
  end

  # O centro pode ter sumido da árvore entre uma edição e outra, então cai para a
  # seleção e daí para a raiz.
  defp focus_center(assigns) do
    existing = MapSet.new(assigns.flattened_nodes, & &1["id"])

    [assigns.focus_center_id, assigns.selected_node_id, root_node_id(assigns.nodes)]
    |> Enum.find(&(is_binary(&1) and MapSet.member?(existing, &1)))
  end

  defp root_node_id([%{"id" => id} | _]), do: id
  defp root_node_id(_), do: nil

  # Remove a relação no formato em que o nó a guarda: `relations` (atual) ou
  # `related_node_ids` (materiais gravados antes da mudança de esquema).
  defp drop_relation(node, target_id) do
    cond do
      is_list(node["relations"]) ->
        Map.put(
          node,
          "relations",
          Enum.reject(node["relations"], &relation_targets?(&1, target_id))
        )

      is_list(node["related_node_ids"]) ->
        Map.put(
          node,
          "related_node_ids",
          Enum.reject(node["related_node_ids"], &(&1 == target_id))
        )

      true ->
        node
    end
  end

  defp relation_targets?(%{"target_id" => id}, target_id), do: id == target_id
  defp relation_targets?(id, target_id) when is_binary(id), do: id == target_id
  defp relation_targets?(_, _), do: false

  defp mark_dirty(socket), do: assign(socket, dirty?: true)

  defp node_stats(flattened) do
    enabled = Enum.count(flattened, &AdaptiveStudy.node_enabled?/1)

    %{
      total: length(flattened),
      enabled: enabled,
      disabled: length(flattened) - enabled
    }
  end

  # Auxiliar recursivo para atualizar nó em árvore
  defp update_node_in_tree(nodes, target_id, update_fn) when is_list(nodes) do
    Enum.map(nodes, fn node ->
      cond do
        node["id"] == target_id ->
          update_fn.(node)

        is_list(node["children"]) ->
          %{node | "children" => update_node_in_tree(node["children"], target_id, update_fn)}

        true ->
          node
      end
    end)
  end

  @impl true
  def render(%{live_action: :map} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 flex flex-col bg-base-200"
      phx-window-keydown="close_node_panel"
      phx-key="Escape"
    >
      <.map_topbar
        material={@material}
        dirty?={@dirty?}
        map_mode={@map_mode}
        selected_node_id={@selected_node_id}
        layout={@map_layout}
        stats={@stats}
        at_root?={focus_center(assigns) == root_node_id(@nodes)}
      />

      <div class="relative flex-1 overflow-hidden">
        <%= if @nodes == [] do %>
          <div class="grid h-full place-items-center p-8 text-center">
            <div class="space-y-2 opacity-60">
              <.icon name="hero-arrow-path" class="mx-auto size-8 motion-safe:animate-spin" />
              <p class="text-sm">A IA ainda está montando o Mapa Mental deste material.</p>
            </div>
          </div>
        <% else %>
          <Mindmap.canvas
            layout={@map_layout}
            selected_id={@selected_node_id}
            origin_id={@focus_origin_id}
            entry_id={focus_center(assigns)}
          />
          <Mindmap.legend layout={@map_layout} />

          <%!-- No telefone a gaveta é uma folha de baixo, não uma coluna: com
               24rem de largura em uma tela de 375px ela cobria o mapa inteiro,
               e ler um nó significava perder de vista onde ele estava. Presa em
               metade da altura, o mapa continua à mostra acima dela. De `sm`
               para cima volta a ser a coluna da direita. --%>
          <aside
            :if={@selected_node}
            id={"map-drawer-#{@selected_node["id"]}"}
            class="absolute inset-x-3 bottom-3 z-20 flex max-h-[55%] flex-col overflow-hidden rounded-3xl border border-base-300 bg-base-100/95 shadow-xl backdrop-blur sm:inset-x-auto sm:right-3 sm:top-3 sm:max-h-none sm:w-[min(24rem,calc(100vw-1.5rem))]"
          >
            <%!-- `close_class` vazio: aqui a gaveta se fecha em qualquer
                 largura, ao contrário da curadoria. --%>
            <.node_panel_bar editing?={@editing_node?} close_class="" />

            <div class="min-h-0 flex-1 space-y-4 overflow-y-auto overscroll-contain p-4">
              <.node_inspector
                node={@selected_node}
                editing?={@editing_node?}
                flattened_nodes={@flattened_nodes}
                book_material_id={@book_material_id}
              />
            </div>
          </aside>
        <% end %>
      </div>
    </div>

    <Layouts.flash_group flash={@flash} />
    <Layouts.notification_stack notifications={@notifications} />
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:adaptive_study} wide={true}>
      <%!-- A partir de `md` a curadoria vira uma área de trabalho de altura de
           tela: a página em si não rola, o cabeçalho e a barra ficam parados e
           as duas colunas rolam cada uma por dentro. É o que evita ter de rolar
           a página inteira para chegar ao fim do detalhamento de um nó.
           3.5rem da navbar (`min-h-14`) + 4rem do `py-8` do <main> = 7.5rem.
           O corte é `md` (768px) e não `lg` porque tablet em retrato tem 768px:
           em `lg` ele caía na pilha e herdava exatamente o problema que a área
           de trabalho resolve. Abaixo de `md` as colunas empilham e a página
           volta a rolar, que é o certo no telefone. --%>
      <%!-- O piso cobre o telefone em paisagem, que passa de 768px de largura e
           entra aqui com ~390px de altura: sem ele as colunas ficariam com uns
           140px cada. Abaixo do piso a página volta a rolar até a área, e as
           colunas rolam por dentro a partir dela. --%>
      <div class="space-y-5 md:flex md:h-[calc(100dvh-7.5rem)] md:min-h-[30rem] md:flex-col md:gap-5 md:space-y-0 md:overflow-hidden">
        <.curation_header material={@material} dirty?={@dirty?} has_nodes?={@nodes != []} />

        <%= if @nodes == [] do %>
          <div class="rounded-3xl border-2 border-dashed border-base-300 bg-base-200/40 p-12 text-center">
            <div class="mx-auto grid size-14 place-items-center rounded-2xl bg-primary/10 text-primary">
              <.icon name="hero-arrow-path" class="size-7 motion-safe:animate-spin" />
            </div>
            <h3 class="mt-4 text-lg font-bold">Mapa Mental ainda não disponível</h3>
            <p class="mx-auto mt-1 max-w-md text-sm opacity-70">
              A IA ainda está decompondo este material. Esta página se atualiza sozinha assim que
              o mapa ficar pronto — você também será avisado por notificação.
            </p>
          </div>
        <% else %>
          <%!-- `min-h-0` é o que permite as colunas encolherem abaixo do próprio
               conteúdo; sem ele o grid cresceria e a rolagem voltaria a ser a
               da página. Em tablet as colunas dividem meio a meio: com o corte
               7/5 do desktop, o painel ficaria em ~300px e os controles do
               cabeçalho do nó quebrariam em três linhas. --%>
          <div class="grid grid-cols-1 items-start gap-5 md:min-h-0 md:flex-1 md:grid-cols-12 md:items-stretch">
            <%!-- Coluna de leitura da curadoria. Mesma anatomia do painel do
                 nó — barra parada no topo, conteúdo rolando por baixo —, que é
                 o que permitiu recolher a barra de ferramentas solta que ficava
                 acima das duas colunas. O acolchoamento menor no telefone
                 devolve largura às linhas, que já perdem espaço para a
                 indentação. --%>
            <div class="card qcard flex min-h-[450px] flex-col overflow-hidden border border-base-300 bg-base-100 md:col-span-6 md:min-h-0 lg:col-span-7">
              <div class="flex min-h-12 shrink-0 items-center gap-2 border-b border-base-300 px-4 py-2">
                <h2 class="flex min-w-0 flex-1 items-center gap-2 truncate text-sm font-bold">
                  <.icon name="hero-bars-3-bottom-left" class="size-4 shrink-0 text-primary" />
                  Sumário do material
                </h2>
              </div>

              <%!-- Rolagem própria só de `md` para cima, onde a coluna tem altura
                   de tela. No telefone quem rola é a página: como caixa de
                   rolagem, o sumário engolia o toque — `flex-1` com base zero o
                   prendia na altura mínima do cartão, e o `overscroll-contain`
                   ainda impedia o gesto de passar adiante, então o dedo não
                   movia nem a lista nem a página. --%>
              <div class="p-3 sm:p-5 md:min-h-0 md:flex-1 md:overflow-y-auto md:overscroll-contain">
                <.outline_view
                  nodes={@nodes}
                  selected_id={@selected_node_id}
                  flattened_nodes={@flattened_nodes}
                  collapsed_ids={@collapsed_ids}
                />
              </div>
            </div>

            <%!-- Detalhamento do nó. No telefone é um modal em folha de baixo:
                 empilhado abaixo do sumário, ler um nó custava rolar a página
                 inteira até passar da árvore e depois voltar para escolher o
                 próximo. De `md` para cima é a coluna da direita de sempre —
                 mesmo markup, só as classes mudam, para não duplicar formulários
                 e IDs no DOM. --%>
            <div
              :if={@selected_node}
              id="node-detail-panel"
              phx-window-keydown={@node_modal_open? && "close_node_panel"}
              phx-key="Escape"
              class={
                [
                  "md:col-span-6 md:min-h-0 lg:col-span-5",
                  if(@node_modal_open?,
                    # z-40 e não z-50 de propósito: as mensagens de flash também
                    # ficam em z-40 e vêm depois no DOM, então continuam por cima
                    # da folha — é nelas que aparece a confirmação de "nó
                    # atualizado" e de "anotação registrada", disparadas de dentro
                    # do próprio painel.
                    do: "fixed inset-0 z-40 flex flex-col justify-end md:static md:z-auto md:block",
                    else: "hidden md:block"
                  )
                ]
              }
            >
              <button
                type="button"
                phx-click="close_node_panel"
                aria-label="Fechar detalhamento"
                class="absolute inset-0 bg-base-content/40 backdrop-blur-[1px] md:hidden"
              ></button>

              <%!-- Barra parada no topo e conteúdo rolando por baixo: o fim de um
                   trecho longo fica sempre a uma rolagem de distância, e o
                   fechar não vai embora junto com o texto. --%>
              <div class="card qcard relative mx-2 mb-2 flex max-h-[90dvh] flex-col overflow-hidden border border-base-300 bg-base-100 md:mx-0 md:mb-0 md:h-full md:max-h-none">
                <%!-- De `md` para cima o painel é a coluna fixa da direita: não
                     há nada a fechar, então sobra só o título na barra. --%>
                <.node_panel_bar editing?={@editing_node?} close_class="md:hidden" />

                <div class="min-h-0 flex-1 overflow-y-auto overscroll-contain p-4 md:p-5">
                  <.node_inspector
                    node={@selected_node}
                    editing?={@editing_node?}
                    flattened_nodes={@flattened_nodes}
                    book_material_id={@book_material_id}
                  />
                </div>
              </div>
            </div>

            <div
              :if={is_nil(@selected_node)}
              class="card qcard hidden border border-base-300 bg-base-100 p-5 md:col-span-6 md:block md:min-h-0 lg:col-span-5"
            >
              <div class="space-y-2 py-12 text-center opacity-50">
                <.icon name="hero-cursor-arrow-rays" class="mx-auto size-8" />
                <p class="text-xs">
                  Selecione um nó para visualizar e editar os dados.
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <.reconstruction_modal
        :if={@show_reconstruction_modal?}
        text={@reconstructed_text}
        stats={@stats}
      />
    </Layouts.app>
    """
  end

  ## Modo imersivo

  defp map_topbar(assigns) do
    ~H"""
    <header class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-base-300 bg-base-100/95 px-3 py-2 backdrop-blur">
      <%!-- No telefone o rótulo sai e fica só a seta: são 11 controles nesta
           barra, e com o texto ela quebrava em quatro linhas, comendo a altura
           que é do mapa (o canvas é o `flex-1` logo abaixo). --%>
      <.link
        id="exit-mindmap-btn"
        patch={~p"/adaptive-study/#{@material.id}/curate"}
        title="Sair do mapa"
        class="btn btn-ghost btn-sm gap-1 rounded-full"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        <span class="hidden sm:inline">Sair do mapa</span>
      </.link>

      <%!-- O bloco de título só aparece quando há largura para ele: no telefone
           ele tomava uma linha inteira sozinho. --%>
      <div class="hidden min-w-0 flex-1 sm:block">
        <p class="truncate text-sm font-bold leading-tight">{@material.title}</p>
        <p class="truncate text-[0.65rem] opacity-60">
          {@stats.total} nós · {length(@layout.relations)} conexões transversais<span :if={
            @layout.hidden_count > 0
          }>
            · {@layout.hidden_count} ocultos em ramos recolhidos
          </span>
        </p>
      </div>

      <div class="join">
        <button
          id="map-mode-tree"
          phx-click="switch_map_mode"
          phx-value-mode="tree"
          title="Formação hierárquica da árvore"
          class={[
            "btn join-item btn-sm gap-1.5",
            if(@map_mode == :tree, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name="hero-share" class="size-4 rotate-90" />
          <span class="hidden sm:inline">Árvore</span>
        </button>
        <button
          id="map-mode-radial"
          phx-click="switch_map_mode"
          phx-value-mode="radial"
          title="Anéis por profundidade em torno da raiz"
          class={[
            "btn join-item btn-sm gap-1.5",
            if(@map_mode == :radial, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name="hero-globe-alt" class="size-4" />
          <span class="hidden sm:inline">Rede</span>
        </button>
        <button
          id="map-mode-focus"
          phx-click="switch_map_mode"
          phx-value-mode="focus"
          title="Aproximar um nó e tudo que se conecta a ele"
          class={[
            "btn join-item btn-sm gap-1.5",
            if(@map_mode == :focus, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name="hero-viewfinder-circle" class="size-4" />
          <span class="hidden sm:inline">Foco</span>
        </button>
      </div>

      <%!-- Só no foco, e só quando há de onde voltar: navegando de nó em nó
           pelo botão de explorar, a raiz fica a muitos saltos de distância e o
           cartão de origem só desfaz um salto por vez. --%>
      <button
        :if={@map_mode == :focus and not @at_root?}
        id="map-focus-root-btn"
        phx-click="focus_root"
        title="Voltar o foco para a raiz do mapa"
        class="btn btn-ghost btn-sm gap-1.5"
      >
        <.icon name="hero-home" class="size-4" />
        <span class="hidden sm:inline">Raiz</span>
      </button>

      <div class="join">
        <button
          id="map-collapse-all"
          phx-click="collapse_all"
          title="Recolher todos os ramos"
          class="btn join-item btn-ghost btn-sm"
        >
          <.icon name="hero-arrows-pointing-in" class="size-4" />
        </button>
        <button
          id="map-expand-all"
          phx-click="expand_all"
          title="Expandir todos os ramos"
          class="btn join-item btn-ghost btn-sm"
        >
          <.icon name="hero-arrows-pointing-out" class="size-4" />
        </button>
      </div>

      <div class="join">
        <button
          title="Afastar"
          phx-click={JS.dispatch("mindmap:zoom", to: "#mindmap-canvas", detail: %{factor: 0.8})}
          class="btn join-item btn-ghost btn-sm"
        >
          <.icon name="hero-magnifying-glass-minus" class="size-4" />
        </button>
        <button
          id="map-fit-btn"
          title="Enquadrar o mapa inteiro"
          phx-click={JS.dispatch("mindmap:fit", to: "#mindmap-canvas")}
          class="btn join-item btn-ghost btn-sm"
        >
          <.icon name="hero-viewfinder-circle" class="size-4" />
        </button>
        <button
          title="Aproximar"
          phx-click={JS.dispatch("mindmap:zoom", to: "#mindmap-canvas", detail: %{factor: 1.25})}
          class="btn join-item btn-ghost btn-sm"
        >
          <.icon name="hero-magnifying-glass-plus" class="size-4" />
        </button>
      </div>

      <button
        id="save-curation-btn"
        phx-click="save_curation"
        class={[
          "btn btn-sm gap-1.5 rounded-full",
          if(@dirty?, do: "btn-primary", else: "btn-primary btn-outline")
        ]}
      >
        <span :if={@dirty?} class="inline-block size-1.5 rounded-full bg-current"></span>
        <.icon name="hero-check" class="size-4" /> Salvar
      </button>
    </header>
    """
  end

  ## Painel do nó — o mesmo componente serve a coluna da curadoria e a gaveta do mapa

  defp node_inspector(assigns) do
    ~H"""
    <%!-- A chave por ID força a troca da subárvore ao mudar de nó, evitando que
         inputs e textareas fiquem com o valor do nó anterior. --%>
    <div id={"node-panel-#{@node["id"]}"} class="space-y-4">
      <.node_panel_header node={@node} editing?={@editing?} />

      <%= if @editing? do %>
        <.node_edit_form node={@node} book_material_id={@book_material_id} />
      <% else %>
        <.node_details node={@node} book_material_id={@book_material_id} />
      <% end %>

      <.cross_references node={@node} flattened_nodes={@flattened_nodes} />

      <.user_notes node={@node} />
    </div>
    """
  end

  ## Cabeçalho e barra de controles

  defp curation_header(assigns) do
    ~H"""
    <%!-- Sem fixação: de `md` para cima ele é o topo de uma área de trabalho que
         não rola, e abaixo disso empilha em várias linhas — congelado, comeria
         a tela do telefone. --%>
    <div class="flex flex-col gap-4 border-b border-base-300 pb-4 md:flex-row md:items-end md:justify-between md:shrink-0">
      <div class="min-w-0 space-y-1.5">
        <.link
          navigate={~p"/adaptive-study"}
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3" /> Voltar aos materiais
        </.link>

        <h1 class="truncate text-2xl font-bold leading-tight tracking-tight">{@material.title}</h1>

        <div class="flex flex-wrap items-center gap-2">
          <span class={[
            "badge badge-sm rounded-full font-semibold",
            if(@material.status == "curated", do: "badge-success", else: "badge-warning")
          ]}>
            {if @material.status == "curated", do: "Curado", else: "Rascunho"}
          </span>

          <span
            :if={@dirty?}
            class="badge badge-sm badge-outline badge-error gap-1.5 rounded-full font-semibold"
          >
            <span class="inline-block size-1.5 rounded-full bg-error motion-safe:animate-pulse"></span>
            Alterações não salvas
          </span>
        </div>
      </div>

      <div class="flex shrink-0 flex-wrap items-center gap-2">
        <.link
          :if={@has_nodes?}
          id="open-mindmap-btn"
          patch={~p"/adaptive-study/#{@material.id}/curate/map"}
          title="Abrir o Mapa Mental em tela cheia"
          class="btn btn-sm inline-flex items-center gap-1.5 rounded-full border-primary/40 bg-primary/10 text-primary hover:bg-primary/20"
        >
          <.icon name="hero-map" class="size-4" />
          Mapa<span class="hidden sm:inline">&nbsp;Mental</span>
        </.link>

        <button
          id="reconstruct-text-btn"
          phx-click="toggle_reconstruction_modal"
          title="Preview do texto reconstruído"
          class="btn btn-outline btn-sm inline-flex items-center gap-1.5 rounded-full"
        >
          <.icon name="hero-document-magnifying-glass" class="size-4" />
          Preview<span class="hidden sm:inline">&nbsp;do Texto</span>
        </button>

        <button
          id="save-curation-btn"
          phx-click="save_curation"
          disabled={not @has_nodes?}
          class={[
            "btn btn-sm inline-flex items-center gap-1.5 rounded-full px-5",
            if(@dirty?, do: "btn-primary", else: "btn-primary btn-outline")
          ]}
        >
          <.icon name="hero-check" class="size-4" />
          Salvar<span class="hidden sm:inline">&nbsp;Curadoria</span>
        </button>
      </div>
    </div>
    """
  end

  ## Visões de leitura da curadoria

  defp outline_view(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-xs opacity-60">
        Clique em um nó para editar o conteúdo ou gerenciar suas conexões.
      </p>

      <div class="space-y-1">
        <.outline_node
          :for={{root_node, index} <- Enum.with_index(@nodes, 1)}
          node={root_node}
          number={to_string(index)}
          selected_id={@selected_id}
          flattened_nodes={@flattened_nodes}
          collapsed_ids={@collapsed_ids}
          depth={0}
        />
      </div>
    </div>
    """
  end

  defp outline_node(assigns) do
    assigns =
      assign(assigns, :collapsed?, outline_collapsed?(assigns.collapsed_ids, assigns.node))

    ~H"""
    <%!-- A indentação encolhe no telefone: a 1.5rem por nível, um ramo de quatro
         níveis comia metade da largura útil e a linha estourava a borda do
         cartão. --%>
    <div class={["space-y-1", @depth > 0 && "ml-1.5 border-l border-base-300 pl-2 sm:ml-3 sm:pl-3"]}>
      <div class="flex items-start gap-1">
        <%!-- O chevron é irmão do bloco clicável, não filho: o JS da LiveView
             não expõe stopPropagation, então aninhá-lo faria um clique para
             recolher também selecionar o nó. --%>
        <button
          :if={children(@node) != []}
          type="button"
          id={"toggle-outline-#{@node["id"]}"}
          phx-click="toggle_collapse"
          phx-value-id={@node["id"]}
          aria-expanded={to_string(not @collapsed?)}
          aria-controls={"outline-children-#{@node["id"]}"}
          title={if @collapsed?, do: "Expandir subnós", else: "Recolher subnós"}
          class="mt-2 grid size-5 shrink-0 place-items-center rounded-md opacity-60 transition hover:bg-base-300 hover:opacity-100"
        >
          <.icon
            name={if @collapsed?, do: "hero-chevron-right", else: "hero-chevron-down"}
            class="size-3.5"
          />
        </button>
        <%!-- Folha ocupa o mesmo espaço do chevron para os rótulos do nível
             alinharem entre si. --%>
        <span :if={children(@node) == []} class="size-5 shrink-0"></span>

        <div
          id={"tree-node-#{@node["id"]}"}
          phx-click="select_node"
          phx-value-id={@node["id"]}
          class={
            [
              # `min-w-0` é o que deixa a linha encolher junto com o cartão: sem ele
              # o item de flex tem largura mínima automática e o conteúdo mais largo
              # (as conexões transversais) empurrava a borda para fora.
              "flex min-w-0 flex-1 cursor-pointer items-start gap-2 rounded-xl border px-2 py-2 transition sm:gap-3 sm:px-3",
              if(@selected_id == @node["id"],
                do: "border-primary bg-primary/10",
                else: "border-transparent hover:border-base-300 hover:bg-base-200/50"
              ),
              not AdaptiveStudy.node_enabled?(@node) && "opacity-50"
            ]
          }
        >
          <span class="mt-0.5 shrink-0 font-mono text-[0.62rem] font-bold text-primary/70 sm:text-[0.7rem]">
            {@number}
          </span>

          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold leading-snug">{@node["label"]}</p>
            <%!-- Duas linhas em vez de uma: numa prévia de uma linha só o texto
                 era cortado antes de dizer do que o nó trata. --%>
            <p
              :if={node_preview(@node) != ""}
              class="line-clamp-2 text-xs leading-relaxed opacity-70"
            >
              {node_preview(@node)}
            </p>

            <%!-- As conexões transversais vinham dos cards. Aqui elas quebram em
                 várias linhas em vez de rolar na horizontal: numa lista hierárquica
                 a rolagem lateral escondia conexão dentro de linha estreita. --%>
            <div :if={relations(@node) != []} class="mt-1.5 flex flex-wrap items-center gap-1">
              <.icon name="hero-link" class="size-3 shrink-0 text-primary/70" />
              <%!-- O badge do daisyUI não quebra linha, então um rótulo de nó
                   longo saía pela borda do cartão em vez de esticar a caixa.
                   Preso à largura disponível, ele corta com reticências — o
                   rótulo inteiro fica no `title`. --%>
              <span
                :for={relation <- relations(@node)}
                class="badge badge-xs badge-secondary max-w-full px-1.5 text-[0.62rem] font-medium"
                title={
                  "#{AdaptiveStudy.relation_label(relation["type"])}: #{find_node_label(@flattened_nodes, relation["target_id"])}"
                }
              >
                <span class="truncate">
                  {find_node_label(@flattened_nodes, relation["target_id"])}
                </span>
              </span>
            </div>
          </div>

          <%!-- Empilhados no telefone: lado a lado, os dois badges tomavam ~75px
               de uma linha que já perdeu largura para a indentação. --%>
          <div class="flex shrink-0 flex-col items-end gap-1 sm:flex-row sm:items-center">
            <%!-- Recolhido, o contador deixa de ser informação de apoio e passa
                 a ser a única pista do que sumiu — por isso ganha destaque. --%>
            <span
              :if={children(@node) != []}
              class={[
                "badge badge-xs font-mono text-[0.6rem]",
                if(@collapsed?, do: "badge-primary", else: "badge-ghost")
              ]}
              title={
                if @collapsed?,
                  do: "#{length(children(@node))} subnó(s) recolhido(s)",
                  else: "#{length(children(@node))} subnó(s)"
              }
            >
              {length(children(@node))}
            </span>
            <%!-- Ícone diferente em cada badge porque as duas cores e os dois
                 textos, sozinhos, não dizem qual é prioridade e qual é
                 complexidade — o mesmo par de ícones do detalhamento do nó
                 (`node_details/1`, "Motivo da Prioridade"/"Motivo da
                 Complexidade"), para o olho já treinado ali reconhecer aqui. --%>
            <div class="flex items-center gap-1">
              <span
                class={[
                  "badge badge-xs gap-0.5 rounded-full text-[0.6rem] font-bold uppercase",
                  priority_badge_class(priority(@node))
                ]}
                title={"Prioridade de estudo: #{priority_label(priority(@node))}"}
              >
                <.icon name="hero-information-circle" class="size-2.5" />
                {priority_label(priority(@node))}
              </span>
              <span
                class={[
                  "badge badge-xs gap-0.5 rounded-full text-[0.6rem] font-bold uppercase",
                  complexity_badge_class(complexity(@node))
                ]}
                title={"Complexidade: #{complexity_label(complexity(@node))}"}
              >
                <.icon name="hero-academic-cap" class="size-2.5" />
                {complexity_label(complexity(@node))}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div :if={not @collapsed?} id={"outline-children-#{@node["id"]}"} class="space-y-1">
        <.outline_node
          :for={{child, index} <- Enum.with_index(children(@node), 1)}
          node={child}
          number={"#{@number}.#{index}"}
          selected_id={@selected_id}
          flattened_nodes={@flattened_nodes}
          collapsed_ids={@collapsed_ids}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end

  ## Painel lateral

  # Barra do painel: fica fora da área de rolagem, então o título e o fechar não
  # somem no meio de um trecho longo — que era o problema de ter o "X" espremido
  # entre os botões de ação, dentro do conteúdo que rola.
  defp node_panel_bar(assigns) do
    ~H"""
    <div class="flex min-h-12 shrink-0 items-center gap-2 border-b border-base-300 px-4 py-2">
      <h3 class="min-w-0 flex-1 truncate text-sm font-bold">
        {if @editing?, do: "Editar Conteúdo", else: "Detalhamento do Nó"}
      </h3>

      <%!-- `btn-sm btn-circle` são 2rem de alvo, contra os 1.5rem do `btn-xs`
           que ele tinha quando morava junto das ações. --%>
      <button
        type="button"
        id="close-node-panel-btn"
        phx-click="close_node_panel"
        aria-label="Fechar detalhamento"
        title="Fechar (Esc)"
        class={["btn btn-ghost btn-sm btn-circle -mr-1.5 shrink-0", @close_class]}
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </div>
    """
  end

  defp node_panel_header(assigns) do
    ~H"""
    <%!-- O ID encolhe antes dos botões e corta com reticências: em nó de ID
         longo era ele que jogava as ações para uma segunda linha. --%>
    <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-b border-base-200 pb-3">
      <span class="min-w-0 flex-1 truncate font-mono text-[0.68rem] font-bold text-primary">
        NÓ ID: {@node["id"]}
      </span>

      <div class="flex shrink-0 items-center gap-2">
        <button
          id={"toggle-node-enabled-#{@node["id"]}"}
          phx-click="toggle_node_enabled"
          phx-value-id={@node["id"]}
          title={
            if AdaptiveStudy.node_enabled?(@node),
              do: "Nó incluído na reconstrução do texto",
              else: "Nó excluído da reconstrução do texto"
          }
          class={[
            "btn btn-sm rounded-full font-semibold",
            if(AdaptiveStudy.node_enabled?(@node),
              do: "btn-success",
              else: "btn-outline btn-error"
            )
          ]}
        >
          {if AdaptiveStudy.node_enabled?(@node), do: "Ativo", else: "Inativo"}
        </button>

        <button
          id="edit-node-btn"
          phx-click="toggle_edit_node"
          class={[
            "btn btn-sm inline-flex items-center gap-1 rounded-lg font-semibold",
            if(@editing?, do: "btn-ghost text-error", else: "btn-outline btn-primary")
          ]}
          title={if @editing?, do: "Cancelar edição", else: "Editar nó"}
        >
          <.icon name={if @editing?, do: "hero-x-mark", else: "hero-pencil-square"} class="size-4" />
          {if @editing?, do: "Cancelar", else: "Editar"}
        </button>
      </div>
    </div>
    """
  end

  defp node_details(assigns) do
    assigns = assign(assigns, :node_text, node_text(assigns.node, assigns.book_material_id))

    ~H"""
    <div class="space-y-4">
      <div class="space-y-2">
        <h4 class="text-lg font-bold leading-snug text-base-content">{@node["label"]}</h4>

        <p :if={(@node["description"] || "") != ""} class="text-xs leading-relaxed opacity-70">
          {@node["description"]}
        </p>

        <div class="flex flex-wrap gap-2">
          <span class={[
            "badge badge-sm shrink-0 rounded-lg px-2.5 py-2 text-[0.65rem] font-semibold uppercase",
            priority_badge_class(priority(@node))
          ]}>
            Prioridade: {priority_label(priority(@node))}
          </span>

          <span class={[
            "badge badge-sm shrink-0 rounded-lg px-2.5 py-2 text-[0.65rem] font-semibold uppercase",
            complexity_badge_class(complexity(@node))
          ]}>
            Complexidade: {complexity_label(complexity(@node))}
          </span>
        </div>
      </div>

      <.reason_box
        icon="hero-information-circle"
        tone="primary"
        title="Motivo da Prioridade de Estudo"
        text={
          value_or(
            @node["priority_reason"],
            "Conceito selecionado com base no peso pedagógico e importância estratégica para retenção."
          )
        }
      />

      <.reason_box
        icon="hero-academic-cap"
        tone="secondary"
        title="Motivo da Complexidade Técnica"
        text={
          value_or(
            @node["complexity_reason"],
            "Classificação determinada a partir da densidade conceitual, nível de abstração e pré-requisitos."
          )
        }
      />

      <%!-- O trecho é o único bloco desta coluna feito para ser lido de ponta a
           ponta, não escaneado: fica sem fundo tingido e sem moldura, separado
           só por uma régua, para o texto competir com o mínimo possível. --%>
      <div class="space-y-3 pt-1">
        <div class="flex items-center justify-between border-b border-base-300 pb-2 text-[0.65rem] uppercase tracking-wider opacity-60">
          <span class="flex items-center gap-1.5 font-bold">
            <.icon name="hero-document-text" class="size-3.5" /> Trecho do material
          </span>
          <span class="font-mono normal-case">
            {String.length(@node_text)} chars
          </span>
        </div>

        <p :if={@node_text == ""} class="text-xs italic opacity-50">
          Este nó não carrega trecho de texto — serve apenas para agrupar subnós.
        </p>
        <.markdown :if={@node_text != ""} content={@node_text} />
      </div>
    </div>
    """
  end

  defp reason_box(assigns) do
    ~H"""
    <div class={[
      "space-y-1 rounded-2xl p-3.5 text-xs",
      if(@tone == "primary",
        do: "border border-primary/20 bg-primary/5",
        else: "border border-secondary/20 bg-secondary/5"
      )
    ]}>
      <span class={[
        "flex items-center gap-1.5 font-bold",
        if(@tone == "primary", do: "text-primary", else: "text-secondary")
      ]}>
        <.icon name={@icon} class="size-4" />
        {@title}
      </span>
      <p class="pl-5 leading-relaxed opacity-80">{@text}</p>
    </div>
    """
  end

  defp node_edit_form(assigns) do
    ~H"""
    <form id="node-edit-form" phx-submit="update_node" class="space-y-4">
      <div class="space-y-1">
        <label class="block text-xs font-semibold opacity-80">Rótulo / Título do Nó</label>
        <input
          type="text"
          name="label"
          value={@node["label"]}
          class="input input-bordered input-sm w-full rounded-xl"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="space-y-1">
          <label class="block text-xs font-semibold opacity-80">Prioridade de Estudo</label>
          <select name="priority" class="select select-bordered select-sm w-full rounded-xl">
            <option
              :for={{value, label} <- priority_options()}
              value={value}
              selected={priority(@node) == value}
            >
              {label}
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="block text-xs font-semibold opacity-80">Complexidade do Tópico</label>
          <select name="complexity" class="select select-bordered select-sm w-full rounded-xl">
            <option
              :for={{value, label} <- complexity_options()}
              value={value}
              selected={complexity(@node) == value}
            >
              {label}
            </option>
          </select>
        </div>
      </div>

      <div class="space-y-1">
        <label class="block text-xs font-semibold opacity-80">Motivo da Prioridade de Estudo</label>
        <textarea
          name="priority_reason"
          rows="2"
          class="textarea textarea-bordered w-full rounded-xl text-xs leading-relaxed"
          placeholder="Explicação do porquê este nó recebeu esta prioridade..."
        >{@node["priority_reason"]}</textarea>
      </div>

      <div class="space-y-1">
        <label class="block text-xs font-semibold opacity-80">Motivo da Complexidade Técnica</label>
        <textarea
          name="complexity_reason"
          rows="2"
          class="textarea textarea-bordered w-full rounded-xl text-xs leading-relaxed"
          placeholder="Explicação do motivo da complexidade atribuída a este nó..."
        >{@node["complexity_reason"]}</textarea>
      </div>

      <div :if={is_nil(@book_material_id)} class="space-y-1">
        <label class="block text-xs font-semibold opacity-80">
          Trecho de Texto Completo (content MD)
        </label>
        <textarea
          name="content"
          rows="6"
          class="textarea textarea-bordered w-full rounded-xl font-mono text-xs leading-relaxed"
        >{@node["content"]}</textarea>
      </div>

      <p :if={@book_material_id} class="text-xs italic opacity-60">
        O trecho deste nó vem dos blocos demarcados no livro — não é editável aqui.
      </p>

      <div class="flex items-center gap-2 pt-1">
        <button
          type="button"
          phx-click="toggle_edit_node"
          class="btn btn-ghost btn-sm flex-1 rounded-xl"
        >
          Cancelar
        </button>
        <button
          type="submit"
          id="save-node-changes-btn"
          class="btn btn-primary btn-sm inline-flex flex-1 items-center justify-center gap-1 rounded-xl"
        >
          <.icon name="hero-check" class="size-4" /> Salvar Alterações
        </button>
      </div>
    </form>
    """
  end

  defp cross_references(assigns) do
    ~H"""
    <div class="space-y-2 border-t border-base-200 pt-4">
      <h4 class="flex items-center gap-1.5 text-xs font-bold text-primary">
        <.icon name="hero-link" class="size-3.5" /> Conexões & Referências Cruzadas
      </h4>

      <p :if={relations(@node) == []} class="text-xs italic opacity-50">
        Nenhum nó relacionado identificado.
      </p>

      <ul :if={relations(@node) != []} class="space-y-1.5">
        <li
          :for={relation <- relations(@node)}
          class="flex items-start gap-2 rounded-xl border border-base-200 bg-base-200/40 px-2.5 py-2"
        >
          <span class={[
            "badge badge-xs shrink-0 font-semibold uppercase text-[0.58rem]",
            relation_badge_class(relation["type"])
          ]}>
            {AdaptiveStudy.relation_label(relation["type"])}
          </span>

          <span class="min-w-0 flex-1 leading-tight">
            <span class="block truncate text-xs font-semibold">
              {find_node_label(@flattened_nodes, relation["target_id"])}
            </span>
            <span :if={relation["label"] != ""} class="block text-[0.65rem] opacity-60">
              {relation["label"]}
            </span>
          </span>

          <button
            type="button"
            id={"remove-cross-ref-#{@node["id"]}-#{relation["target_id"]}"}
            phx-click="remove_cross_reference"
            phx-value-target_id={relation["target_id"]}
            title="Remover esta conexão"
            class="grid size-4 shrink-0 place-items-center rounded-full opacity-50 transition hover:bg-base-300 hover:opacity-100"
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp user_notes(assigns) do
    ~H"""
    <div class="space-y-2 border-t border-base-200 pt-4">
      <h4 class="flex items-center gap-1.5 text-xs font-bold text-primary">
        <.icon name="hero-pencil-square" class="size-3.5" /> Minhas Anotações Pessoais
      </h4>

      <form id={"user-notes-form-#{@node["id"]}"} phx-submit="save_user_notes" class="space-y-2">
        <textarea
          name="user_notes"
          rows="3"
          class="textarea textarea-bordered w-full rounded-xl text-xs leading-relaxed focus:textarea-primary"
          placeholder="Escreva suas observações, lembretes ou resumos adicionais sobre este tópico..."
        >{@node["user_notes"] || ""}</textarea>

        <div class="flex justify-end">
          <button
            type="submit"
            id="save-user-notes-btn"
            class="btn btn-xs btn-primary inline-flex items-center gap-1 rounded-lg font-semibold"
          >
            <.icon name="hero-check" class="size-3" /> Salvar Anotação
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp reconstruction_modal(assigns) do
    ~H"""
    <div
      class="modal modal-open"
      phx-window-keydown="close_reconstruction_modal"
      phx-key="Escape"
    >
      <div class="modal-box max-w-3xl space-y-4 rounded-3xl">
        <div class="flex items-center justify-between gap-3 border-b border-base-200 pb-3">
          <h3 class="flex items-center gap-2 text-lg font-bold">
            <.icon name="hero-document-check" class="size-5 text-primary" />
            Reconstrução Completa do Texto Original
          </h3>
          <button
            type="button"
            phx-click="close_reconstruction_modal"
            class="btn btn-sm btn-circle btn-ghost"
            aria-label="Fechar"
          >
            ✕
          </button>
        </div>

        <p class="text-xs opacity-70">
          Texto remontado a partir da junção, em ordem, do conteúdo dos nós folhas ativos.
          <span :if={@stats.disabled > 0} class="font-semibold text-warning">
            {@stats.disabled} nó(s) marcado(s) como inativo(s) ficaram de fora.
          </span>
        </p>

        <%!-- Aqui se lê o material inteiro de uma vez, então a altura sobe e a
             coluna de texto é centralizada na medida de leitura do .qprose. --%>
        <div class="max-h-[65vh] overflow-y-auto rounded-2xl border border-base-300 px-6 py-7">
          <p :if={@text == ""} class="text-xs italic opacity-60">
            Nenhum conteúdo ativo para reconstruir.
          </p>
          <.markdown :if={@text != ""} content={@text} class="mx-auto" />
        </div>

        <div class="modal-action items-center justify-between">
          <span class="font-mono text-[0.65rem] opacity-60">{String.length(@text)} caracteres</span>
          <button
            type="button"
            phx-click="close_reconstruction_modal"
            class="btn btn-primary btn-sm rounded-full px-6"
          >
            Fechar Preview
          </button>
        </div>
      </div>

      <button
        type="button"
        phx-click="close_reconstruction_modal"
        class="modal-backdrop"
        aria-label="Fechar preview"
      >
        Fechar
      </button>
    </div>
    """
  end

  ## Helpers de apresentação

  defp priority(node), do: Map.get(node, "priority") || "medium"
  defp complexity(node), do: Map.get(node, "complexity") || "moderate"
  defp children(node), do: Map.get(node, "children") || []
  defp relations(node), do: AdaptiveStudy.node_relations(node)

  defp value_or(nil, fallback), do: fallback
  defp value_or("", fallback), do: fallback
  defp value_or(value, _fallback), do: value

  defp priority_options, do: [{"high", "Alta"}, {"medium", "Média"}, {"low", "Baixa"}]

  defp complexity_options,
    do: [{"easy", "Fácil"}, {"moderate", "Intermediário"}, {"complex", "Avançado"}]

  defp priority_label("high"), do: "Alta"
  defp priority_label("low"), do: "Baixa"
  defp priority_label(_), do: "Média"

  defp priority_badge_class("high"), do: "badge-primary"
  defp priority_badge_class("low"), do: "badge-ghost"
  defp priority_badge_class(_), do: "badge-warning"

  defp complexity_label("easy"), do: "Fácil"
  defp complexity_label("complex"), do: "Avançado"
  defp complexity_label(_), do: "Intermediário"

  defp relation_badge_class("prerequisito"), do: "badge-warning"
  defp relation_badge_class("aprofunda"), do: "badge-primary"
  defp relation_badge_class("contrasta"), do: "badge-error"
  defp relation_badge_class("exemplifica"), do: "badge-success"
  defp relation_badge_class("aplica"), do: "badge-info"
  defp relation_badge_class(_), do: "badge-secondary"

  defp complexity_badge_class("easy"), do: "badge-success"
  defp complexity_badge_class("complex"), do: "badge-error"
  defp complexity_badge_class(_), do: "badge-info"

  defp node_preview(node) do
    (node["description"] || node["content"] || "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 120)
  end

  defp find_node_label(nodes, id) do
    case Enum.find(nodes, &(&1["id"] == id)) do
      nil -> id
      node -> node["label"] || id
    end
  end

  # Só nó com filhos pode estar recolhido: um ID de folha em `collapsed_ids`
  # (resíduo de uma edição que removeu os subnós) não deve esconder nada.
  defp outline_collapsed?(collapsed_ids, node),
    do: children(node) != [] and MapSet.member?(collapsed_ids, node["id"])
end
