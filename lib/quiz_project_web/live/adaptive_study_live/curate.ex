defmodule QuizProjectWeb.AdaptiveStudyLive.Curate do
  use QuizProjectWeb, :live_view

  import QuizProjectWeb.Components.Markdown, only: [markdown: 1]

  alias Phoenix.LiveView.JS
  alias QuizProject.AdaptiveStudy
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
        nodes = get_in(material.mindmap_tree, ["nodes"]) || []
        first = List.first(AdaptiveStudy.flatten_nodes(nodes))

        {:ok,
         socket
         |> assign(
           page_title: "Curadoria: " <> material.title,
           material: material,
           view_mode: :cards,
           map_mode: :tree,
           focus_center_id: nil,
           focus_origin_id: nil,
           collapsed_ids: MindmapLayout.initial_collapsed(nodes),
           editing_node?: false,
           dirty?: false,
           show_reconstruction_modal?: false
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
          focus_center_id: nil,
          focus_origin_id: nil
        )
      else
        socket
      end

    {:noreply, assign_map_layout(socket)}
  end

  @impl true
  def handle_event("switch_view", %{"mode" => mode}, socket) do
    new_mode =
      case mode do
        "outline" -> :outline
        "mermaid" -> :mermaid
        _ -> :cards
      end

    {:noreply, assign(socket, view_mode: new_mode)}
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
    # Mantém o primeiro nível aberto: recolher a raiz esconderia o mapa inteiro.
    collapsed = MapSet.new(MindmapLayout.branch_ids(socket.assigns.nodes, 1))

    {:noreply, socket |> assign(collapsed_ids: collapsed) |> assign_map_layout()}
  end

  @impl true
  def handle_event("select_node", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.flattened_nodes, &(&1["id"] == id))

    {:noreply,
     socket
     |> assign(selected_node_id: id, selected_node: node, editing_node?: false)
     |> assign_map_layout()}
  end

  @impl true
  def handle_event("close_node_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_node_id: nil, selected_node: nil, editing_node?: false)
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
          nodes = get_in(reloaded.mindmap_tree, ["nodes"]) || []
          first = List.first(AdaptiveStudy.flatten_nodes(nodes))

          {:noreply,
           socket
           |> assign(
             material: reloaded,
             page_title: "Curadoria: " <> reloaded.title,
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
      reconstructed_text: AdaptiveStudy.reconstruct_raw_text(nodes),
      mermaid_code: AdaptiveStudy.to_mermaid(nodes)
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
          />
          <Mindmap.legend layout={@map_layout} />

          <aside
            :if={@selected_node}
            id={"map-drawer-#{@selected_node["id"]}"}
            class="absolute bottom-3 right-3 top-3 z-20 flex w-[min(24rem,calc(100vw-1.5rem))] flex-col overflow-hidden rounded-3xl border border-base-300 bg-base-100/95 shadow-xl backdrop-blur"
          >
            <div class="flex-1 space-y-4 overflow-y-auto p-4">
              <.node_inspector
                node={@selected_node}
                editing?={@editing_node?}
                flattened_nodes={@flattened_nodes}
                closable?={true}
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
      <div class="space-y-5">
        <.curation_header material={@material} dirty?={@dirty?} has_nodes?={@nodes != []} />

        <.curation_toolbar
          :if={@nodes != []}
          view_mode={@view_mode}
          stats={@stats}
          material={@material}
        />

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
          <div class="grid grid-cols-1 items-start gap-5 lg:grid-cols-12">
            <%!-- Coluna de leitura da curadoria (cards, sumário ou diagrama) --%>
            <div class="card qcard min-h-[450px] border border-base-300 bg-base-100 p-5 lg:col-span-7">
              <%= cond do %>
                <% @view_mode == :cards -> %>
                  <.cards_view
                    nodes={@nodes}
                    selected_id={@selected_node_id}
                    flattened_nodes={@flattened_nodes}
                  />
                <% @view_mode == :outline -> %>
                  <.outline_view nodes={@nodes} selected_id={@selected_node_id} />
                <% true -> %>
                  <.mermaid_view mermaid_code={@mermaid_code} />
              <% end %>
            </div>

            <%!-- Painel lateral do nó selecionado --%>
            <div class="card qcard border border-base-300 bg-base-100 p-5 lg:sticky lg:top-4 lg:col-span-5">
              <%= if @selected_node do %>
                <.node_inspector
                  node={@selected_node}
                  editing?={@editing_node?}
                  flattened_nodes={@flattened_nodes}
                  closable?={false}
                />
              <% else %>
                <div class="space-y-2 py-12 text-center opacity-50">
                  <.icon name="hero-cursor-arrow-rays" class="mx-auto size-8" />
                  <p class="text-xs">
                    Selecione um nó para visualizar e editar os dados.
                  </p>
                </div>
              <% end %>
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
      <.link
        id="exit-mindmap-btn"
        patch={~p"/adaptive-study/#{@material.id}/curate"}
        class="btn btn-ghost btn-sm gap-1 rounded-full"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Sair do mapa
      </.link>

      <div class="min-w-0 flex-1">
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
          class={[
            "btn join-item btn-sm gap-1.5",
            if(@map_mode == :tree, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name="hero-share" class="size-4 rotate-90" /> Árvore
        </button>
        <button
          id="map-mode-radial"
          phx-click="switch_map_mode"
          phx-value-mode="radial"
          class={[
            "btn join-item btn-sm gap-1.5",
            if(@map_mode == :radial, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name="hero-globe-alt" class="size-4" /> Rede
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
          <.icon name="hero-viewfinder-circle" class="size-4" /> Foco
        </button>
      </div>

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
      <.node_panel_header node={@node} editing?={@editing?} closable?={@closable?} />

      <%= if @editing? do %>
        <.node_edit_form node={@node} />
      <% else %>
        <.node_details node={@node} />
      <% end %>

      <.cross_references node={@node} flattened_nodes={@flattened_nodes} />

      <.user_notes node={@node} />
    </div>
    """
  end

  ## Cabeçalho e barra de controles

  defp curation_header(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 border-b border-base-300 pb-4 md:flex-row md:items-end md:justify-between">
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
          class="btn btn-sm inline-flex items-center gap-1.5 rounded-full border-primary/40 bg-primary/10 text-primary hover:bg-primary/20"
        >
          <.icon name="hero-map" class="size-4" /> Abrir Mapa Mental
        </.link>

        <button
          id="reconstruct-text-btn"
          phx-click="toggle_reconstruction_modal"
          class="btn btn-outline btn-sm inline-flex items-center gap-1.5 rounded-full"
        >
          <.icon name="hero-document-magnifying-glass" class="size-4" /> Preview do Texto
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
          <.icon name="hero-check" class="size-4" /> Salvar Curadoria
        </button>
      </div>
    </div>
    """
  end

  defp curation_toolbar(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 rounded-2xl border border-base-300 bg-base-200/60 p-2 sm:flex-row sm:items-center sm:justify-between">
      <%!-- Estas três são visões de leitura da curadoria, não de navegação: os
           nomes antigos ("Grafo", "Árvore") prometiam um mapa que elas não
           entregam. O mapa navegável mora no modo imersivo. --%>
      <div class="join">
        <.view_tab
          id="view-cards-mode"
          mode="cards"
          active?={@view_mode == :cards}
          icon="hero-rectangle-stack"
        >
          Cards
        </.view_tab>
        <.view_tab
          id="view-outline-mode"
          mode="outline"
          active?={@view_mode == :outline}
          icon="hero-bars-3-bottom-left"
        >
          Sumário
        </.view_tab>
        <.view_tab
          id="view-mermaid-mode"
          mode="mermaid"
          active?={@view_mode == :mermaid}
          icon="hero-chart-bar"
        >
          Diagrama
        </.view_tab>
      </div>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-2 text-xs font-medium">
        <span class="opacity-70">{@stats.total} nós mapeados</span>
        <span class="inline-flex items-center gap-1.5">
          <span class="inline-block size-1.5 rounded-full bg-success"></span>
          {@stats.enabled} ativos
        </span>
        <span :if={@stats.disabled > 0} class="inline-flex items-center gap-1.5 opacity-70">
          <span class="inline-block size-1.5 rounded-full bg-base-content/40"></span>
          {@stats.disabled} fora da reconstrução
        </span>
      </div>
    </div>
    """
  end

  defp view_tab(assigns) do
    ~H"""
    <button
      id={@id}
      phx-click="switch_view"
      phx-value-mode={@mode}
      class={[
        "btn join-item btn-sm inline-flex items-center gap-2",
        if(@active?, do: "btn-primary", else: "btn-ghost")
      ]}
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  ## Visões de leitura da curadoria

  defp cards_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-wrap items-center justify-between gap-2 border-b border-base-200 pb-2 text-xs opacity-70">
        <span>Clique em um nó para editar ou gerenciar referências.</span>
        <div class="flex items-center gap-3">
          <span class="flex items-center gap-1">
            <span class="inline-block size-2.5 rounded-full bg-primary"></span> Alta
          </span>
          <span class="flex items-center gap-1">
            <span class="inline-block size-2.5 rounded-full bg-warning"></span> Média
          </span>
          <span class="flex items-center gap-1">
            <span class="inline-block size-2.5 rounded-full bg-base-300"></span> Baixa
          </span>
        </div>
      </div>

      <div id="curation-cards-list" class="space-y-3 pt-1">
        <.card_node
          :for={root_node <- @nodes}
          node={root_node}
          selected_id={@selected_id}
          flattened_nodes={@flattened_nodes}
          depth={0}
        />
      </div>
    </div>
    """
  end

  defp card_node(assigns) do
    ~H"""
    <div class={["space-y-3", @depth > 0 && "ml-4 border-l-2 border-primary/15 pl-4"]}>
      <div
        id={"node-card-#{@node["id"]}"}
        phx-click="select_node"
        phx-value-id={@node["id"]}
        class={[
          "max-w-full cursor-pointer space-y-2 overflow-hidden rounded-2xl border p-3.5 transition",
          if(@selected_id == @node["id"],
            do: "border-primary bg-primary/10 shadow-sm",
            else: "border-base-300 bg-base-100 hover:border-primary/50 hover:bg-base-200/40"
          ),
          not AdaptiveStudy.node_enabled?(@node) && "border-dashed opacity-50"
        ]}
      >
        <div class="flex items-center justify-between gap-3">
          <div class="flex min-w-0 items-center gap-2">
            <span class={["size-2.5 shrink-0 rounded-full", priority_dot_class(priority(@node))]}></span>
            <span class="truncate text-sm font-bold">{@node["label"]}</span>
          </div>

          <div class="flex shrink-0 items-center gap-1">
            <span
              :if={not AdaptiveStudy.node_enabled?(@node)}
              class="badge badge-xs badge-ghost text-[0.6rem] font-semibold uppercase"
            >
              Inativo
            </span>
            <span class={[
              "badge badge-xs text-[0.6rem] font-semibold uppercase",
              priority_badge_class(priority(@node))
            ]}>
              {priority_label(priority(@node))}
            </span>
          </div>
        </div>

        <div :if={relations(@node) != []} class="flex items-center gap-1.5 overflow-x-auto pb-1">
          <span class="flex shrink-0 items-center gap-1 text-[0.65rem] font-semibold uppercase tracking-wider opacity-60">
            <.icon name="hero-link" class="size-3 text-primary" /> Conexões:
          </span>
          <span
            :for={relation <- relations(@node)}
            class="badge badge-sm badge-secondary shrink-0 px-2 py-1 text-[0.68rem] font-medium"
            title={AdaptiveStudy.relation_label(relation["type"])}
          >
            {find_node_label(@flattened_nodes, relation["target_id"])}
          </span>
        </div>
      </div>

      <div :if={children(@node) != []} class="space-y-3">
        <.card_node
          :for={child <- children(@node)}
          node={child}
          selected_id={@selected_id}
          flattened_nodes={@flattened_nodes}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end

  defp outline_view(assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="flex items-center gap-2 border-b border-base-200 pb-2 text-sm font-bold text-primary">
        <.icon name="hero-bars-3-bottom-left" class="size-4" /> Sumário Hierárquico do Conteúdo
      </h3>

      <div class="space-y-1">
        <.outline_node
          :for={{root_node, index} <- Enum.with_index(@nodes, 1)}
          node={root_node}
          number={to_string(index)}
          selected_id={@selected_id}
          depth={0}
        />
      </div>
    </div>
    """
  end

  defp outline_node(assigns) do
    ~H"""
    <div class={["space-y-1", @depth > 0 && "ml-3 border-l border-base-300 pl-3"]}>
      <div
        id={"tree-node-#{@node["id"]}"}
        phx-click="select_node"
        phx-value-id={@node["id"]}
        class={[
          "flex cursor-pointer items-start gap-3 rounded-xl border px-3 py-2 transition",
          if(@selected_id == @node["id"],
            do: "border-primary bg-primary/10",
            else: "border-transparent hover:border-base-300 hover:bg-base-200/50"
          ),
          not AdaptiveStudy.node_enabled?(@node) && "opacity-50"
        ]}
      >
        <span class="mt-0.5 shrink-0 font-mono text-[0.7rem] font-bold text-primary/70">
          {@number}
        </span>

        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-semibold leading-snug">{@node["label"]}</p>
          <p :if={node_preview(@node) != ""} class="truncate text-xs opacity-60">
            {node_preview(@node)}
          </p>
        </div>

        <div class="flex shrink-0 items-center gap-1">
          <span
            :if={children(@node) != []}
            class="badge badge-xs badge-ghost font-mono text-[0.6rem]"
            title="Subnós"
          >
            {length(children(@node))}
          </span>
          <span class={[
            "badge badge-xs rounded-full text-[0.6rem] font-bold uppercase",
            priority_badge_class(priority(@node))
          ]}>
            {priority_label(priority(@node))}
          </span>
        </div>
      </div>

      <.outline_node
        :for={{child, index} <- Enum.with_index(children(@node), 1)}
        node={child}
        number={"#{@number}.#{index}"}
        selected_id={@selected_id}
        depth={@depth + 1}
      />
    </div>
    """
  end

  defp mermaid_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <p class="border-b border-base-200 pb-2 text-xs font-medium opacity-70">
        Diagrama dinâmico em Mermaid (hierarquia sólida, referências cruzadas tracejadas).
      </p>

      <div
        id="mermaid-diagram-container"
        phx-hook=".MermaidDiagram"
        data-mermaid={@mermaid_code}
        class="w-full rounded-2xl border border-base-300 bg-base-200/40 p-4"
      >
        <%!-- phx-update="ignore": sem isso, cada patch da LiveView apagava o SVG
             renderizado pelo Mermaid e a área voltava para o estado de carregamento. --%>
        <div
          id="mermaid-diagram-target"
          phx-update="ignore"
          class="flex min-h-[380px] w-full items-center justify-center overflow-x-auto"
        >
          <span class="flex items-center gap-2 text-xs opacity-50">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" />
            Renderizando diagrama Mermaid...
          </span>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".MermaidDiagram">
        export default {
          mounted() {
            this.renderDiagram();
          },
          updated() {
            this.renderDiagram();
          },
          loadMermaid() {
            if (window.mermaid) return Promise.resolve(window.mermaid);

            if (!window.__mermaidLoader) {
              window.__mermaidLoader = new Promise((resolve, reject) => {
                const script = document.createElement("script");
                script.src = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js";
                script.onload = () => resolve(window.mermaid);
                script.onerror = () => reject(new Error("Falha ao carregar a biblioteca Mermaid."));
                document.head.appendChild(script);
              });
            }

            return window.__mermaidLoader;
          },
          async renderDiagram() {
            const target = this.el.querySelector("#mermaid-diagram-target");
            const code = this.el.getAttribute("data-mermaid");
            if (!target || !code) return;

            const theme = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "default";
            if (code === this.lastCode && theme === this.lastTheme) return;

            const renderId = "mermaid-svg-" + Math.random().toString(36).slice(2);

            try {
              const mermaid = await this.loadMermaid();
              mermaid.initialize({startOnLoad: false, theme: theme, securityLevel: "strict"});
              const {svg} = await mermaid.render(renderId, code);
              target.innerHTML = svg;
              this.lastCode = code;
              this.lastTheme = theme;
            } catch (error) {
              // O Mermaid deixa o nó de trabalho no body quando a renderização falha.
              document.getElementById("d" + renderId)?.remove();
              this.lastCode = null;
              target.innerHTML = "";
              const message = document.createElement("div");
              message.className = "text-xs text-error font-mono p-3";
              message.textContent = "Erro ao renderizar diagrama Mermaid: " + error.message;
              target.appendChild(message);
            }
          }
        }
      </script>

      <details class="rounded-xl border border-base-300 bg-base-200/30 p-3 text-xs">
        <summary class="cursor-pointer font-mono font-bold opacity-70">
          Ver Código-Fonte Mermaid (.mmd)
        </summary>
        <pre class="mt-2 overflow-x-auto whitespace-pre rounded-lg bg-base-300 p-3 font-mono text-[0.7rem]">{@mermaid_code}</pre>
      </details>
    </div>
    """
  end

  ## Painel lateral

  defp node_panel_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3 border-b border-base-200 pb-3">
      <div class="min-w-0 space-y-0.5">
        <span class="block truncate font-mono text-[0.68rem] font-bold text-primary">
          NÓ ID: {@node["id"]}
        </span>
        <h3 class="text-base font-bold leading-tight">
          {if @editing?, do: "Editar Conteúdo", else: "Detalhamento do Nó"}
        </h3>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        <button
          :if={@closable?}
          type="button"
          id="close-node-panel-btn"
          phx-click="close_node_panel"
          title="Fechar painel (Esc)"
          class="btn btn-ghost btn-xs btn-circle"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>

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
            "btn btn-xs rounded-full font-semibold",
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
            "btn btn-xs inline-flex items-center gap-1 rounded-lg font-semibold",
            if(@editing?, do: "btn-ghost text-error", else: "btn-outline btn-primary")
          ]}
          title={if @editing?, do: "Cancelar edição", else: "Editar nó"}
        >
          <.icon name={if @editing?, do: "hero-x-mark", else: "hero-pencil-square"} class="size-3.5" />
          {if @editing?, do: "Cancelar", else: "Editar"}
        </button>
      </div>
    </div>
    """
  end

  defp node_details(assigns) do
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

      <div class="space-y-2 rounded-2xl border border-base-300 bg-base-200/40 p-4">
        <div class="flex items-center justify-between border-b border-base-200 pb-2 text-xs opacity-70">
          <span class="flex items-center gap-1 font-bold text-primary">
            <.icon name="hero-document-text" class="size-3.5" /> Conteúdo Atômico (MD)
          </span>
          <span class="font-mono text-[0.65rem]">
            {String.length(@node["content"] || "")} chars
          </span>
        </div>

        <p :if={(@node["content"] || "") == ""} class="pt-1 text-xs italic opacity-50">
          Este nó não carrega trecho de texto — serve apenas para agrupar subnós.
        </p>
        <div :if={(@node["content"] || "") != ""} class="pt-1">
          <.markdown content={@node["content"]} />
        </div>
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

      <div class="space-y-1">
        <label class="block text-xs font-semibold opacity-80">
          Trecho de Texto Completo (content MD)
        </label>
        <textarea
          name="content"
          rows="6"
          class="textarea textarea-bordered w-full rounded-xl font-mono text-xs leading-relaxed"
        >{@node["content"]}</textarea>
      </div>

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

        <div class="max-h-[450px] overflow-y-auto rounded-2xl border border-base-300 bg-base-200/60 p-5">
          <p :if={@text == ""} class="text-xs italic opacity-60">
            Nenhum conteúdo ativo para reconstruir.
          </p>
          <.markdown :if={@text != ""} content={@text} />
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

  defp priority_dot_class("high"), do: "bg-primary"
  defp priority_dot_class("low"), do: "bg-base-300"
  defp priority_dot_class(_), do: "bg-warning"

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
end
