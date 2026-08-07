defmodule QuizProject.AdaptiveStudy.MindmapLayout do
  @moduledoc """
  Calcula as posições dos nós do mapa mental para as visões de navegação.

  Dois modos:

    * `:tree` — árvore horizontal, raiz à esquerda e ramos crescendo para a
      direita. Cada folha visível ocupa uma linha; o pai fica centralizado entre
      o primeiro e o último filho (layout clássico de mapa mental).
    * `:radial` — anéis concêntricos por profundidade. Cada nó recebe uma fatia
      angular proporcional à quantidade de folhas que carrega, então ramos densos
      ganham mais espaço e o mapa não se sobrepõe.

  A saída é puramente geométrica, em pixels: a LiveView posiciona os cartões em
  HTML absoluto e desenha as arestas em um SVG atrás deles. Nada aqui depende de
  Phoenix, então o layout é testável isoladamente.

  Coordenadas `x`/`y` são sempre o **centro** do nó.
  """

  alias QuizProject.AdaptiveStudy

  @padding 140
  @anchor_gap 7

  # Na árvore toda ligação usa duas portas fixas: sai pela borda direita (logo
  # depois do círculo do alternador, de raio 11) e entra pela borda esquerda.
  # Nenhum traço atravessa cartão, então o cartão pode ficar translúcido.
  @tree_exit_gap 13
  @tree_entry_gap 8

  # Espaçamento da árvore horizontal
  @col_gap 300
  @row_gap 86
  @tree_size {216, 64}

  # Vizinhança (modo foco)
  @focus_size {216, 64}
  @focus_min_radius 340
  @focus_spread 2.2

  # Anéis do radial
  @ring_min 210
  @radial_arc 190
  @radial_size {172, 56}

  @type mode :: :tree | :radial

  @doc """
  Monta o layout dos `nodes` no `mode` pedido, ocultando os filhos dos nós cujo
  ID estiver em `collapsed_ids`.
  """
  @spec build(list(), mode(), MapSet.t()) :: map()
  def build(nodes, mode \\ :tree, collapsed_ids \\ MapSet.new())

  def build(nodes, mode, collapsed_ids) when is_list(nodes) do
    tree = prune(nodes, collapsed_ids)
    {node_width, node_height} = node_size(mode)

    placed =
      case mode do
        :radial -> place_radial(tree)
        _ -> tree |> place_tree(0, 0) |> elem(0)
      end

    {placed, width, height} = normalize(placed, node_width, node_height)
    positions = Map.new(placed, &{&1.id, &1})

    %{
      mode: mode,
      nodes: placed,
      edges: hierarchy_edges(tree, positions, mode, {node_width / 2, node_height / 2}),
      relations: relation_edges(placed, positions, mode, {node_width / 2, node_height / 2}),
      width: width,
      height: height,
      node_width: node_width,
      node_height: node_height,
      collapsed_count: Enum.count(placed, & &1.collapsed?),
      hidden_count:
        placed |> Enum.filter(& &1.collapsed?) |> Enum.map(& &1.children_count) |> Enum.sum(),
      # Muda quando o desenho muda de tamanho ou de composição: é o gatilho que o
      # hook usa para reenquadrar em vez de preservar o pan/zoom do usuário.
      signature: "#{mode}-#{width}x#{height}-#{length(placed)}"
    }
  end

  def build(_nodes, mode, _collapsed_ids), do: build([], mode, MapSet.new())

  @doc """
  Vizinhança do nó `selected_id`: ele no centro e, ao redor, só quem se conecta
  direto a ele — o pai e as relações que chegam à esquerda, os subnós e as
  relações que saem à direita, espelhando o "entra pela frente, sai por trás" da
  árvore.

  Sem seleção (ou com um ID que não existe mais) cai para a árvore inteira, que é
  o estado seguro.
  """
  @spec focus(list(), String.t() | nil) :: map()
  def focus(nodes, selected_id) when is_list(nodes) do
    flat = AdaptiveStudy.flatten_nodes(nodes)
    index = Map.new(flat, &{&1["id"], &1})

    case index[selected_id] do
      nil -> build(nodes, :tree)
      center -> focus_layout(flat, index, center)
    end
  end

  def focus(_nodes, _selected_id), do: build([], :tree)

  defp focus_layout(flat, index, center) do
    center_id = center["id"]
    parents = parent_index(flat)
    {node_width, node_height} = @focus_size

    incoming = incoming_relations(flat, center_id)
    outgoing = outgoing_relations(center, index, center_id)

    # Hierarquia tem precedência: um subnó que também é alvo de relação continua
    # aparecendo como subnó, do lado de quem sai.
    left = neighbors([index[parents[center_id]]], incoming, index, [center_id])
    taken = [center_id | Enum.map(left, & &1.id)]
    right = neighbors(Map.get(center, "children") || [], outgoing, index, taken)

    radius = focus_radius(max(length(left), length(right)), node_height)

    placed =
      [focus_placed(center, 0.0, 0.0, 0)] ++
        fan(left, :math.pi(), radius) ++ fan(right, 0.0, radius)

    {placed, width, height} = normalize(placed, node_width, node_height)
    positions = Map.new(placed, &{&1.id, &1})
    half = {node_width / 2, node_height / 2}

    %{
      mode: :focus,
      nodes: placed,
      edges: focus_edges(placed, positions, center_id, parents, half),
      relations: focus_relations(placed, positions, center_id, incoming, outgoing, half),
      width: width,
      height: height,
      node_width: node_width,
      node_height: node_height,
      collapsed_count: 0,
      hidden_count: 0,
      signature: "focus-#{center_id}-#{width}x#{height}-#{length(placed)}"
    }
  end

  defp parent_index(flat) do
    Enum.reduce(flat, %{}, fn node, acc ->
      Enum.reduce(Map.get(node, "children") || [], acc, fn child, inner ->
        Map.put(inner, child["id"], node["id"])
      end)
    end)
  end

  defp outgoing_relations(center, index, center_id) do
    center
    |> AdaptiveStudy.node_relations()
    |> Enum.filter(&(&1["target_id"] != center_id and is_map_key(index, &1["target_id"])))
    |> Enum.map(&{&1["target_id"], &1})
  end

  defp incoming_relations(flat, center_id) do
    Enum.flat_map(flat, fn node ->
      if node["id"] == center_id do
        []
      else
        node
        |> AdaptiveStudy.node_relations()
        |> Enum.filter(&(&1["target_id"] == center_id))
        |> Enum.map(&{node["id"], &1})
      end
    end)
  end

  # Junta vizinhos de hierarquia e de relação em uma lista sem repetição.
  defp neighbors(hierarchy_nodes, relations, index, taken) do
    from_tree = hierarchy_nodes |> Enum.reject(&is_nil/1) |> Enum.map(&focus_item/1)
    seen = MapSet.new(taken ++ Enum.map(from_tree, & &1.id))

    from_relations =
      relations
      |> Enum.map(fn {id, _relation} -> index[id] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1["id"])
      |> Enum.reject(&MapSet.member?(seen, &1["id"]))
      |> Enum.map(&focus_item/1)

    from_tree ++ from_relations
  end

  defp focus_item(node), do: %{id: node["id"], node: node}

  # Leque simétrico em torno de `base`: um vizinho vai no eixo, vários se abrem
  # sobre o arco.
  defp fan([], _base, _radius), do: []

  defp fan([single], base, radius) do
    [focus_placed(single.node, radius * :math.cos(base), radius * :math.sin(base))]
  end

  defp fan(items, base, radius) do
    step = @focus_spread / (length(items) - 1)
    start = base - @focus_spread / 2

    items
    |> Enum.with_index()
    |> Enum.map(fn {item, position} ->
      angle = start + position * step

      focus_placed(item.node, radius * :math.cos(angle), radius * :math.sin(angle))
    end)
  end

  defp focus_radius(count, _node_height) when count <= 1, do: @focus_min_radius * 1.0

  defp focus_radius(count, node_height) do
    max(@focus_min_radius * 1.0, count * (node_height + 30) / @focus_spread)
  end

  defp focus_placed(node, x, y, depth \\ 1) do
    %{
      id: node["id"],
      node: node,
      x: x,
      y: y,
      depth: depth,
      collapsed?: false,
      children_count: length(Map.get(node, "children") || [])
    }
  end

  defp focus_edges(placed, positions, center_id, parents, half) do
    Enum.flat_map(placed, fn %{id: id} ->
      cond do
        id == center_id ->
          []

        parents[center_id] == id ->
          [focus_edge(id, center_id, positions, half)]

        parents[id] == center_id ->
          [focus_edge(center_id, id, positions, half)]

        true ->
          []
      end
    end)
  end

  defp focus_edge(from_id, to_id, positions, half) do
    %{
      id: "#{from_id}->#{to_id}",
      from_id: from_id,
      to_id: to_id,
      path: hierarchy_path(:radial, positions[from_id], positions[to_id], half)
    }
  end

  defp focus_relations(placed, positions, center_id, incoming, outgoing, half) do
    shown = MapSet.new(placed, & &1.id)

    (Enum.map(incoming, fn {source_id, relation} -> {source_id, center_id, relation} end) ++
       Enum.map(outgoing, fn {target_id, relation} -> {center_id, target_id, relation} end))
    |> Enum.filter(fn {from_id, to_id, _} ->
      MapSet.member?(shown, from_id) and MapSet.member?(shown, to_id)
    end)
    |> Enum.map(fn {from_id, to_id, relation} ->
      # `:focus` cai na cláusula do radial: quadrática deslocada, que é o traço
      # certo para um arranjo em volta de um centro.
      :focus
      |> relation_path(positions[from_id], positions[to_id], half)
      |> Map.merge(%{
        id: "#{from_id}~#{to_id}",
        from_id: from_id,
        to_id: to_id,
        type: relation["type"],
        label: relation["label"]
      })
    end)
  end

  @doc """
  IDs que devem começar recolhidos: em mapas grandes, tudo a partir do terceiro
  nível, para a primeira tela caber sem virar um emaranhado.
  """
  @spec initial_collapsed(list(), pos_integer()) :: MapSet.t()
  def initial_collapsed(nodes, threshold \\ 24) when is_list(nodes) do
    if length(AdaptiveStudy.flatten_nodes(nodes)) <= threshold do
      MapSet.new()
    else
      MapSet.new(branch_ids(nodes, 2))
    end
  end

  @doc """
  IDs dos nós que têm filhos (ou seja, que podem ser recolhidos) a partir da
  profundidade `min_depth`, contada a partir de zero.
  """
  @spec branch_ids(list(), non_neg_integer()) :: [String.t()]
  def branch_ids(nodes, min_depth \\ 0) when is_list(nodes),
    do: collect_branch_ids(nodes, min_depth, 0)

  defp collect_branch_ids(nodes, min_depth, depth) do
    Enum.flat_map(nodes, fn node ->
      children = Map.get(node, "children") || []
      deeper = collect_branch_ids(children, min_depth, depth + 1)

      if depth >= min_depth and children != [], do: [node["id"] | deeper], else: deeper
    end)
  end

  defp node_size(:focus), do: @focus_size
  defp node_size(:radial), do: @radial_size
  defp node_size(_), do: @tree_size

  ## Poda: aplica os nós recolhidos e guarda quantos filhos ficaram escondidos

  defp prune(nodes, collapsed) do
    Enum.map(nodes, fn node ->
      all_children = Map.get(node, "children") || []
      collapsed? = all_children != [] and MapSet.member?(collapsed, node["id"])

      %{
        id: node["id"],
        node: node,
        collapsed?: collapsed?,
        children_count: length(all_children),
        children: if(collapsed?, do: [], else: prune(all_children, collapsed))
      }
    end)
  end

  defp leaf_count(%{children: []}), do: 1
  defp leaf_count(%{children: children}), do: Enum.sum(Enum.map(children, &leaf_count/1))

  ## Árvore horizontal

  # Percorre em profundidade mantendo um contador de linhas: folhas consomem uma
  # linha cada e o pai assume o ponto médio entre o primeiro e o último filho.
  defp place_tree(items, depth, row) do
    Enum.reduce(items, {[], row}, fn item, {acc, current_row} ->
      {children, next_row} = place_tree(item.children, depth + 1, current_row)

      {y, next_row} =
        case Enum.filter(children, &(&1.depth == depth + 1)) do
          [] -> {current_row * @row_gap * 1.0, current_row + 1}
          direct -> {(List.first(direct).y + List.last(direct).y) / 2, next_row}
        end

      {acc ++ [placed(item, depth * @col_gap * 1.0, y, depth) | children], next_row}
    end)
  end

  ## Radial

  defp place_radial([]), do: []

  defp place_radial(items) do
    base = radial_base(items)
    full = 2 * :math.pi()

    case items do
      [single] ->
        [placed(single, 0.0, 0.0, 0) | radial_ring(single.children, 1, base, 0.0, full)]

      many ->
        radial_ring(many, 1, base, 0.0, full)
    end
  end

  defp radial_ring([], _depth, _base, _from, _to), do: []

  defp radial_ring(items, depth, base, from, to) do
    total = items |> Enum.map(&leaf_count/1) |> Enum.sum() |> max(1)
    span = to - from
    radius = depth * base

    items
    |> Enum.reduce({[], from}, fn item, {acc, start} ->
      slice = span * leaf_count(item) / total
      angle = start + slice / 2

      self =
        placed(
          item,
          radius * :math.cos(angle),
          radius * :math.sin(angle),
          depth
        )

      children = radial_ring(item.children, depth + 1, base, start, start + slice)
      {acc ++ [self | children], start + slice}
    end)
    |> elem(0)
  end

  # O raio base precisa ser grande o bastante para o anel mais cheio caber sem
  # sobreposição: circunferência (2·π·r) dividida pelos nós daquele anel.
  defp radial_base(items) do
    items
    |> depth_counts(1, %{})
    |> Enum.reduce(@ring_min * 1.0, fn {depth, count}, acc ->
      max(acc, count * @radial_arc / (2 * :math.pi() * depth))
    end)
  end

  defp depth_counts([], _depth, acc), do: acc

  defp depth_counts(items, depth, acc) do
    acc = Map.update(acc, depth, length(items), &(&1 + length(items)))

    Enum.reduce(items, acc, fn item, inner ->
      depth_counts(item.children, depth + 1, inner)
    end)
  end

  defp placed(item, x, y, depth) do
    %{
      id: item.id,
      node: item.node,
      x: x,
      y: y,
      depth: depth,
      collapsed?: item.collapsed?,
      children_count: item.children_count
    }
  end

  ## Normalização e arestas

  defp normalize([], _width, _height), do: {[], 2 * @padding, 2 * @padding}

  defp normalize(placed, node_width, node_height) do
    xs = Enum.map(placed, & &1.x)
    ys = Enum.map(placed, & &1.y)
    offset_x = @padding + node_width / 2 - Enum.min(xs)
    offset_y = @padding + node_height / 2 - Enum.min(ys)

    placed = Enum.map(placed, &%{&1 | x: &1.x + offset_x, y: &1.y + offset_y})

    width = Enum.max(xs) - Enum.min(xs) + node_width + 2 * @padding
    height = Enum.max(ys) - Enum.min(ys) + node_height + 2 * @padding

    {placed, round(width), round(height)}
  end

  defp hierarchy_edges(tree, positions, mode, half) do
    tree
    |> parent_child_pairs()
    |> Enum.flat_map(fn {parent_id, child_id} ->
      with %{} = parent <- positions[parent_id],
           %{} = child <- positions[child_id] do
        [
          %{
            id: "#{parent_id}->#{child_id}",
            from_id: parent_id,
            to_id: child_id,
            path: hierarchy_path(mode, parent, child, half)
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp parent_child_pairs(items) do
    Enum.flat_map(items, fn item ->
      Enum.map(item.children, &{item.id, &1.id}) ++ parent_child_pairs(item.children)
    end)
  end

  # Toda aresta começa e termina em um ponto FORA do cartão. Ancorar no centro
  # obrigava a linha a passar por baixo do cartão, que então precisava ser
  # translúcido para a linha não parecer cortada — e o mapa ficava sujo.
  defp hierarchy_path(:radial, parent, child, {hw, hh}) do
    {x1, y1} = border_point(parent, child.x - parent.x, child.y - parent.y, hw, hh)
    {x2, y2} = border_point(child, parent.x - child.x, parent.y - child.y, hw, hh)

    "M#{r(x1)},#{r(y1)} L#{r(x2)},#{r(y2)}"
  end

  defp hierarchy_path(_mode, parent, child, {hw, _hh}) do
    x1 = parent.x + hw + @tree_exit_gap
    x2 = child.x - hw - @tree_entry_gap
    ctrl = (x2 - x1) / 2

    "M#{r(x1)},#{r(parent.y)} C#{r(x1 + ctrl)},#{r(parent.y)} #{r(x2 - ctrl)},#{r(child.y)} #{r(x2)},#{r(child.y)}"
  end

  defp relation_edges(placed, positions, mode, half) do
    Enum.flat_map(placed, fn %{id: source_id, node: node} ->
      node
      |> AdaptiveStudy.node_relations()
      |> Enum.flat_map(fn relation ->
        target_id = relation["target_id"]

        with true <- target_id != source_id,
             %{} = source <- positions[source_id],
             %{} = target <- positions[target_id] do
          [
            relation_path(mode, source, target, half)
            |> Map.merge(%{
              id: "#{source_id}~#{target_id}",
              from_id: source_id,
              to_id: target_id,
              type: relation["type"],
              label: relation["label"]
            })
          ]
        else
          _ -> []
        end
      end)
    end)
  end

  # Na árvore a relação usa as mesmas portas da hierarquia — sai por trás do
  # cartão de origem e entra pela frente do de destino — só que tracejada e
  # colorida. O laço horizontal cobre também a referência "para trás", quando o
  # destino está à esquerda da origem.
  defp relation_path(:tree, source, target, {hw, _hh}) do
    x1 = source.x + hw + @tree_exit_gap
    x2 = target.x - hw - @tree_entry_gap
    bow = max(110.0, abs(x2 - x1) / 2)
    c1 = x1 + bow
    c2 = x2 - bow

    %{
      path:
        "M#{r(x1)},#{r(source.y)} C#{r(c1)},#{r(source.y)} #{r(c2)},#{r(target.y)} #{r(x2)},#{r(target.y)}",
      from_x: r(x1),
      from_y: r(source.y),
      to_x: r(x2),
      to_y: r(target.y),
      # Ponto da cúbica em t = 0.5: (p0 + 3·c1 + 3·c2 + p3) / 8.
      label_x: r((x1 + 3 * c1 + 3 * c2 + x2) / 8),
      label_y: r((source.y + target.y) / 2)
    }
  end

  # No radial, curva quadrática deslocada na perpendicular para a relação não se
  # confundir com a hierarquia. As pontas são ancoradas na direção do ponto de
  # controle, que é a tangente real da curva ali — assim ela sai perpendicular à
  # borda do cartão.
  defp relation_path(_radial, source, target, {hw, hh}) do
    dx = target.x - source.x
    dy = target.y - source.y
    length = max(:math.sqrt(dx * dx + dy * dy), 1.0)
    offset = min(120.0, length * 0.25)

    ctrl_x = (source.x + target.x) / 2 - dy / length * offset
    ctrl_y = (source.y + target.y) / 2 + dx / length * offset

    {x1, y1} = border_point(source, ctrl_x - source.x, ctrl_y - source.y, hw, hh)
    {x2, y2} = border_point(target, ctrl_x - target.x, ctrl_y - target.y, hw, hh)

    %{
      path: "M#{r(x1)},#{r(y1)} Q#{r(ctrl_x)},#{r(ctrl_y)} #{r(x2)},#{r(y2)}",
      from_x: r(x1),
      from_y: r(y1),
      to_x: r(x2),
      to_y: r(y2),
      # Ponto da curva em t = 0.5, onde o rótulo da relação fica centralizado.
      label_x: r(0.25 * x1 + 0.5 * ctrl_x + 0.25 * x2),
      label_y: r(0.25 * y1 + 0.5 * ctrl_y + 0.25 * y2)
    }
  end

  # Onde a semirreta que sai do centro do nó na direção (dx, dy) cruza a borda do
  # cartão, mais uma folga para o traço não encostar nele.
  defp border_point(node, dx, dy, hw, hh) do
    length = :math.sqrt(dx * dx + dy * dy)

    if length < 0.001 do
      {node.x, node.y}
    else
      to_side = if abs(dx) < 0.001, do: 1.0e9, else: hw / abs(dx)
      to_top = if abs(dy) < 0.001, do: 1.0e9, else: hh / abs(dy)
      scale = min(to_side, to_top) + @anchor_gap / length

      {node.x + dx * scale, node.y + dy * scale}
    end
  end

  defp r(value), do: Float.round(value * 1.0, 1)
end
