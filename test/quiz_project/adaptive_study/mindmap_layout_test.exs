defmodule QuizProject.AdaptiveStudy.MindmapLayoutTest do
  use ExUnit.Case, async: true

  alias QuizProject.AdaptiveStudy.MindmapLayout

  defp tree do
    [
      %{
        "id" => "root",
        "label" => "Raiz",
        "relations" => [%{"target_id" => "b2", "type" => "contrasta", "label" => "opõe-se"}],
        "children" => [
          %{
            "id" => "b1",
            "label" => "Ramo 1",
            "children" => [
              %{"id" => "b1_1", "label" => "Folha 1", "children" => []},
              %{"id" => "b1_2", "label" => "Folha 2", "children" => []}
            ]
          },
          %{"id" => "b2", "label" => "Ramo 2", "children" => []}
        ]
      }
    ]
  end

  describe "modo árvore" do
    test "posiciona por profundidade e centraliza o pai entre os filhos" do
      layout = MindmapLayout.build(tree(), :tree)
      by_id = Map.new(layout.nodes, &{&1.id, &1})

      assert map_size(by_id) == 5
      assert by_id["root"].depth == 0
      assert by_id["b1"].depth == 1
      assert by_id["b1_1"].depth == 2

      # profundidades diferentes ocupam colunas diferentes, na ordem
      assert by_id["root"].x < by_id["b1"].x
      assert by_id["b1"].x < by_id["b1_1"].x
      assert by_id["b1"].x == by_id["b2"].x

      # o pai fica exatamente no meio do primeiro e do último filho
      assert by_id["b1"].y == (by_id["b1_1"].y + by_id["b1_2"].y) / 2
      assert by_id["root"].y == (by_id["b1"].y + by_id["b2"].y) / 2
    end

    test "folhas não se sobrepõem em y" do
      layout = MindmapLayout.build(tree(), :tree)
      ys = layout.nodes |> Enum.filter(&(&1.depth == 2)) |> Enum.map(& &1.y)

      assert length(Enum.uniq(ys)) == length(ys)
    end

    test "gera uma aresta por par pai/filho e uma curva por relação transversal" do
      layout = MindmapLayout.build(tree(), :tree)

      assert length(layout.edges) == 4
      assert Enum.all?(layout.edges, &String.starts_with?(&1.path, "M"))

      assert [relation] = layout.relations
      assert relation.from_id == "root"
      assert relation.to_id == "b2"
      assert relation.type == "contrasta"
      # na árvore a relação usa as mesmas portas da hierarquia: cúbica horizontal
      assert relation.path =~ "C"
      assert relation.from_x > relation.to_x or relation.from_y != relation.to_y
    end

    test "aceita o formato antigo de referência cruzada" do
      nodes = [
        %{"id" => "a", "label" => "A", "related_node_ids" => ["b"], "children" => []},
        %{"id" => "b", "label" => "B", "children" => []}
      ]

      assert [relation] = MindmapLayout.build(nodes, :tree).relations
      assert relation.type == "relacionado"
    end

    test "descarta relações para nós inexistentes ou ocultos" do
      nodes = [
        %{
          "id" => "a",
          "label" => "A",
          "relations" => [
            %{"target_id" => "fantasma", "type" => "aplica"},
            %{"target_id" => "a", "type" => "aplica"}
          ],
          "children" => []
        }
      ]

      assert MindmapLayout.build(nodes, :tree).relations == []
    end
  end

  describe "recolhimento de ramos" do
    test "oculta os descendentes e registra quantos ficaram escondidos" do
      layout = MindmapLayout.build(tree(), :tree, MapSet.new(["b1"]))
      ids = Enum.map(layout.nodes, & &1.id)

      assert "b1" in ids
      refute "b1_1" in ids
      refute "b1_2" in ids

      b1 = Enum.find(layout.nodes, &(&1.id == "b1"))
      assert b1.collapsed?
      assert b1.children_count == 2
      assert layout.hidden_count == 2
    end

    test "recolher um nó sem filhos não muda nada" do
      full = MindmapLayout.build(tree(), :tree)
      same = MindmapLayout.build(tree(), :tree, MapSet.new(["b2"]))

      assert Enum.map(full.nodes, & &1.id) == Enum.map(same.nodes, & &1.id)
      assert same.hidden_count == 0
    end

    test "initial_collapsed/2 só recolhe a partir do 3º nível em mapas grandes" do
      # árvore pequena continua toda aberta
      assert MindmapLayout.initial_collapsed(tree()) == MapSet.new()

      deep = [
        %{
          "id" => "n0",
          "children" => [
            %{
              "id" => "n1",
              "children" => [
                %{"id" => "n2", "children" => [%{"id" => "n3", "children" => []}]}
              ]
            }
          ]
        }
      ]

      collapsed = MindmapLayout.initial_collapsed(deep, 2)

      # n2 está no 3º nível (depth 2) e tem filhos: recolhe
      assert MapSet.member?(collapsed, "n2")
      # níveis acima seguem abertos, e folha não tem o que recolher
      refute MapSet.member?(collapsed, "n0")
      refute MapSet.member?(collapsed, "n1")
      refute MapSet.member?(collapsed, "n3")
    end
  end

  test "no radial a relação é uma quadrática deslocada, não a cúbica da árvore" do
    assert [relation] = MindmapLayout.build(tree(), :radial).relations
    assert relation.path =~ "Q"
  end

  describe "modo radial" do
    test "distribui os nós em anéis equidistantes da raiz única" do
      layout = MindmapLayout.build(tree(), :radial)
      by_id = Map.new(layout.nodes, &{&1.id, &1})
      root = by_id["root"]

      # todo nó da mesma profundidade fica no mesmo anel...
      assert_in_delta radius(by_id["b1"], root), radius(by_id["b2"], root), 0.5
      assert_in_delta radius(by_id["b1_1"], root), radius(by_id["b1_2"], root), 0.5

      # ...e anéis mais profundos ficam mais longe do centro
      assert radius(by_id["b1"], root) < radius(by_id["b1_1"], root)
    end

    test "nós do mesmo anel guardam distância entre si" do
      nodes = [
        %{
          "id" => "root",
          "label" => "Raiz",
          "children" =>
            Enum.map(1..12, &%{"id" => "n#{&1}", "label" => "N#{&1}", "children" => []})
        }
      ]

      layout = MindmapLayout.build(nodes, :radial)
      ring = Enum.filter(layout.nodes, &(&1.depth == 1))

      distances =
        for a <- ring, b <- ring, a.id < b.id do
          :math.sqrt(:math.pow(a.x - b.x, 2) + :math.pow(a.y - b.y, 2))
        end

      assert Enum.min(distances) > layout.node_height
    end
  end

  describe "modo foco" do
    test "centraliza o nó e traz só quem se conecta direto a ele" do
      layout = MindmapLayout.focus(tree(), "b1")
      ids = Enum.map(layout.nodes, & &1.id)

      assert layout.mode == :focus
      # b1 no centro, com o pai (root) e os dois subnós ao redor
      assert Enum.sort(ids) == ["b1", "b1_1", "b1_2", "root"]
      # b2 não se conecta a b1: fica de fora
      refute "b2" in ids

      center = Enum.find(layout.nodes, &(&1.id == "b1"))
      assert center.depth == 0
      assert Enum.all?(layout.nodes -- [center], &(&1.depth == 1))
    end

    test "o pai fica à esquerda do centro e os subnós à direita" do
      layout = MindmapLayout.focus(tree(), "b1")
      by_id = Map.new(layout.nodes, &{&1.id, &1})

      assert by_id["root"].x < by_id["b1"].x
      assert by_id["b1_1"].x > by_id["b1"].x
      assert by_id["b1_2"].x > by_id["b1"].x
    end

    test "traz os parceiros de relação, nos dois sentidos" do
      # root -contrasta-> b2
      saindo = MindmapLayout.focus(tree(), "root")
      assert "b2" in Enum.map(saindo.nodes, & &1.id)
      assert [%{from_id: "root", to_id: "b2", type: "contrasta"}] = saindo.relations

      chegando = MindmapLayout.focus(tree(), "b2")
      assert "root" in Enum.map(chegando.nodes, & &1.id)
      assert [%{from_id: "root", to_id: "b2"}] = chegando.relations
    end

    test "vizinho que é subnó e alvo de relação aparece uma vez só" do
      nodes = [
        %{
          "id" => "a",
          "label" => "A",
          "relations" => [%{"target_id" => "b", "type" => "aprofunda"}],
          "children" => [%{"id" => "b", "label" => "B", "children" => []}]
        }
      ]

      layout = MindmapLayout.focus(nodes, "a")
      ids = Enum.map(layout.nodes, & &1.id)

      assert ids == Enum.uniq(ids)
      assert Enum.sort(ids) == ["a", "b"]
    end

    test "nó isolado gera só ele mesmo, sem estourar" do
      nodes = [%{"id" => "solo", "label" => "Solo", "children" => []}]
      layout = MindmapLayout.focus(nodes, "solo")

      assert [%{id: "solo"}] = layout.nodes
      assert layout.edges == []
      assert layout.relations == []
      assert layout.width > 0
    end

    test "longe da raiz, ela entra solta como âncora de volta" do
      nodes = [
        %{
          "id" => "root",
          "label" => "Raiz",
          "children" => [
            %{
              "id" => "a",
              "label" => "A",
              "children" => [%{"id" => "a1", "label" => "A1", "children" => []}]
            }
          ]
        }
      ]

      layout = MindmapLayout.focus(nodes, "a1")
      root = Enum.find(layout.nodes, &(&1.id == "root"))

      assert root.detached?
      # solta de verdade: nenhuma aresta nem relação a menciona
      ligados =
        Enum.flat_map(layout.edges, &[&1.from_id, &1.to_id]) ++
          Enum.flat_map(layout.relations, &[&1.from_id, &1.to_id])

      refute "root" in ligados
      # e acima do centro, para não se misturar aos vizinhos dos lados
      assert root.y < Enum.find(layout.nodes, &(&1.id == "a1")).y
    end

    test "com ligação real, a raiz entra ligada e não duplica" do
      nodes = [
        %{
          "id" => "root",
          "label" => "Raiz",
          "children" => [%{"id" => "a", "label" => "A", "children" => []}]
        }
      ]

      layout = MindmapLayout.focus(nodes, "a")
      root = Enum.find(layout.nodes, &(&1.id == "root"))

      refute root.detached?
      assert Enum.count(layout.nodes, &(&1.id == "root")) == 1
      assert Enum.any?(layout.edges, &(&1.from_id == "root" and &1.to_id == "a"))
    end

    test "centrado na própria raiz, ela não vira âncora de si mesma" do
      layout = MindmapLayout.focus(tree(), "root")

      assert Enum.count(layout.nodes, &(&1.id == "root")) == 1
      refute Enum.find(layout.nodes, &(&1.id == "root")).detached?
    end

    test "sem seleção válida cai para a árvore inteira" do
      assert MindmapLayout.focus(tree(), nil).mode == :tree
      assert MindmapLayout.focus(tree(), "fantasma").mode == :tree
    end

    test "a assinatura muda quando o centro muda, para o canvas reenquadrar" do
      refute MindmapLayout.focus(tree(), "b1").signature ==
               MindmapLayout.focus(tree(), "b2").signature
    end

    test "muitos vizinhos afastam o anel em vez de sobrepor" do
      nodes = [
        %{
          "id" => "root",
          "label" => "Raiz",
          "children" =>
            Enum.map(1..10, &%{"id" => "n#{&1}", "label" => "N#{&1}", "children" => []})
        }
      ]

      layout = MindmapLayout.focus(nodes, "root")
      ring = Enum.filter(layout.nodes, &(&1.depth == 1))

      distances =
        for a <- ring, b <- ring, a.id < b.id do
          :math.sqrt(:math.pow(a.x - b.x, 2) + :math.pow(a.y - b.y, 2))
        end

      assert Enum.min(distances) > layout.node_height
    end
  end

  describe "ancoragem das arestas" do
    # Nenhum traço pode nascer ou morrer dentro do cartão: se nascesse, ficaria
    # escondido atrás dele e o cartão teria que ser translúcido para a linha não
    # parecer cortada.
    for mode <- [:tree, :radial] do
      test "no modo #{mode} nenhuma extremidade cai dentro de um cartão" do
        layout = MindmapLayout.build(tree(), unquote(mode))
        boxes = Enum.map(layout.nodes, &{&1.x, &1.y})
        hw = layout.node_width / 2
        hh = layout.node_height / 2

        endpoints =
          Enum.flat_map(layout.edges ++ layout.relations, fn edge ->
            [start_point(edge.path), end_point(edge.path)]
          end)

        assert endpoints != []

        for {px, py} <- endpoints, {cx, cy} <- boxes do
          refute abs(px - cx) < hw and abs(py - cy) < hh,
                 "ponta (#{px}, #{py}) caiu dentro do cartão em (#{cx}, #{cy})"
        end
      end
    end

    test "a ponta que marca a direção da relação fica na borda, não no centro" do
      layout = MindmapLayout.build(tree(), :tree)
      [relation] = layout.relations
      target = Enum.find(layout.nodes, &(&1.id == relation.to_id))

      refute {relation.to_x, relation.to_y} == {target.x, target.y}

      assert abs(relation.to_x - target.x) >= layout.node_width / 2 or
               abs(relation.to_y - target.y) >= layout.node_height / 2
    end
  end

  test "árvore vazia gera um layout vazio, sem estourar" do
    layout = MindmapLayout.build([], :tree)

    assert layout.nodes == []
    assert layout.edges == []
    assert layout.width > 0
    assert layout.height > 0
  end

  # "M12.5,30 C..." -> {12.5, 30.0}
  defp start_point("M" <> rest), do: rest |> String.split(" ", parts: 2) |> hd() |> to_point()

  # última coordenada do comando final (C x1,y1 x2,y2 x,y  ou  Q cx,cy x,y  ou  L x,y)
  defp end_point(path), do: path |> String.split(" ") |> List.last() |> to_point()

  defp to_point(pair) do
    [x, y] = pair |> String.replace(~r/^[A-Z]/, "") |> String.split(",")
    {String.to_float(x), String.to_float(y)}
  end

  defp radius(node, origin),
    do: :math.sqrt(:math.pow(node.x - origin.x, 2) + :math.pow(node.y - origin.y, 2))
end
