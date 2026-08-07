defmodule QuizProject.AdaptiveStudyTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.AdaptiveStudy

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        email: "estudante@teste.com",
        name: "Estudante Teste",
        password: "Password123!"
      })

    %{user: user}
  end

  test "cria, busca, lista, atualiza e deleta material de estudo", %{user: user} do
    assert {:ok, material} =
             AdaptiveStudy.create_material(user, %{
               title: "Elixir OTP",
               raw_content: "Parágrafo 1 de OTP.\n\nParágrafo 2 de GenServer.",
               summary: "Resumo OTP",
               mindmap_tree: %{
                 "nodes" => [
                   %{
                     "id" => "node_1",
                     "label" => "OTP",
                     "content" => "",
                     "order" => 0,
                     "children" => [
                       %{
                         "id" => "node_1_1",
                         "label" => "Nó 1",
                         "content" => "Parágrafo 1 de OTP.",
                         "order" => 1,
                         "children" => []
                       },
                       %{
                         "id" => "node_1_2",
                         "label" => "Nó 2",
                         "content" => "Parágrafo 2 de GenServer.",
                         "order" => 2,
                         "children" => []
                       }
                     ]
                   }
                 ]
               }
             })

    assert material.title == "Elixir OTP"
    assert material.user_id == user.id

    assert [fetched] = AdaptiveStudy.list_materials(user)
    assert fetched.id == material.id

    assert {:ok, found} = AdaptiveStudy.get_material(material.id, user)
    assert found.id == material.id

    assert {:ok, updated} =
             AdaptiveStudy.update_material(
               found,
               %{status: "curated", title: "Elixir OTP Curado"},
               user
             )

    assert updated.status == "curated"
    assert updated.title == "Elixir OTP Curado"

    assert {:ok, _} = AdaptiveStudy.delete_material(updated, user)
    assert AdaptiveStudy.list_materials(user) == []
  end

  test "reconstruct_raw_text/1 reconstrói o texto original concatenando os nós folhas na ordem",
       %{user: _user} do
    tree = %{
      "nodes" => [
        %{
          "id" => "root",
          "label" => "Raiz",
          "content" => "",
          "order" => 0,
          "children" => [
            %{
              "id" => "n1",
              "label" => "Parte 1",
              "content" => "Primeira frase do documento.",
              "order" => 1,
              "children" => []
            },
            %{
              "id" => "n2",
              "label" => "Parte 2",
              "content" => "Segunda frase do documento.",
              "order" => 2,
              "children" => []
            }
          ]
        }
      ]
    }

    reconstructed = AdaptiveStudy.reconstruct_raw_text(tree["nodes"])
    assert reconstructed == "Primeira frase do documento.\n\nSegunda frase do documento."
  end

  test "reconstruct_raw_text/1 ignora nós desativados e subárvores desativadas" do
    nodes = [
      %{"id" => "n1", "content" => "Fica.", "order" => 1, "children" => []},
      %{"id" => "n2", "content" => "Sai.", "order" => 2, "enabled" => false, "children" => []},
      %{
        "id" => "n3",
        "content" => "",
        "order" => 3,
        "enabled" => false,
        "children" => [%{"id" => "n3_1", "content" => "Filho de nó desativado.", "order" => 4}]
      }
    ]

    assert AdaptiveStudy.reconstruct_raw_text(nodes) == "Fica."
  end

  test "reconstruct_raw_text/1 não gera separadores em branco para folhas sem conteúdo" do
    nodes = [
      %{"id" => "n1", "content" => "Um.", "order" => 1, "children" => []},
      %{"id" => "n2", "content" => "   ", "order" => 2, "children" => []},
      %{"id" => "n3", "content" => nil, "order" => 3, "children" => []},
      %{"id" => "n4", "content" => "Dois.", "order" => 4, "children" => []}
    ]

    assert AdaptiveStudy.reconstruct_raw_text(nodes) == "Um.\n\nDois."
  end

  test "to_mermaid/1 descarta referências cruzadas para IDs inexistentes" do
    nodes = [
      %{
        "id" => "n1",
        "label" => "Raiz",
        "related_node_ids" => ["n2", "fantasma", "n1"],
        "children" => [%{"id" => "n2", "label" => "Filho", "children" => []}]
      }
    ]

    mermaid = AdaptiveStudy.to_mermaid(nodes)

    assert mermaid =~ "node_n1 --> node_n2"
    assert mermaid =~ "node_n1 -. relacionado .-> node_n2"
    refute mermaid =~ "fantasma"
    # nó não referencia a si mesmo
    refute mermaid =~ "-.-> node_n1"
  end

  test "to_mermaid/1 usa o tipo da relação como rótulo da aresta" do
    nodes = [
      %{
        "id" => "n1",
        "label" => "A",
        "relations" => [%{"target_id" => "n2", "type" => "prerequisito"}],
        "children" => [%{"id" => "n2", "label" => "B", "children" => []}]
      }
    ]

    assert AdaptiveStudy.to_mermaid(nodes) =~ "node_n1 -. pré-requisito .-> node_n2"
  end

  describe "node_relations/1" do
    test "normaliza o formato atual, com tipo e rótulo" do
      node = %{
        "relations" => [
          %{"target_id" => "b", "type" => "contrasta", "label" => "caminho oposto"}
        ]
      }

      assert AdaptiveStudy.node_relations(node) == [
               %{"target_id" => "b", "type" => "contrasta", "label" => "caminho oposto"}
             ]
    end

    test "converte o formato antigo related_node_ids" do
      assert AdaptiveStudy.node_relations(%{"related_node_ids" => ["b"]}) == [
               %{"target_id" => "b", "type" => "relacionado", "label" => ""}
             ]
    end

    test "descarta entradas malformadas e tipos desconhecidos" do
      node = %{
        "relations" => [
          %{"target_id" => "b", "type" => "inventado"},
          %{"type" => "aplica"},
          "solto",
          42
        ]
      }

      assert AdaptiveStudy.node_relations(node) == [
               %{"target_id" => "b", "type" => "relacionado", "label" => ""},
               %{"target_id" => "solto", "type" => "relacionado", "label" => ""}
             ]
    end

    test "relations tem precedência sobre related_node_ids" do
      node = %{
        "relations" => [%{"target_id" => "novo", "type" => "aplica"}],
        "related_node_ids" => ["antigo"]
      }

      assert [%{"target_id" => "novo"}] = AdaptiveStudy.node_relations(node)
    end
  end

  test "node_type/1 cai para conceito quando o tipo é desconhecido ou ausente" do
    assert AdaptiveStudy.node_type(%{"node_type" => "processo"}) == "processo"
    assert AdaptiveStudy.node_type(%{"node_type" => "inventado"}) == "conceito"
    assert AdaptiveStudy.node_type(%{}) == "conceito"
  end

  test "to_mermaid/1 marca nós desativados e sanitiza rótulos" do
    nodes = [
      %{"id" => "n1", "label" => "Diz \"olá\"\ne quebra linha", "children" => []},
      %{"id" => "n2", "label" => String.duplicate("a", 100), "enabled" => false, "children" => []}
    ]

    mermaid = AdaptiveStudy.to_mermaid(nodes)

    assert mermaid =~ "node_n1[\"Diz 'olá' e quebra linha\"]"
    assert mermaid =~ "classDef disabled"
    assert mermaid =~ "class node_n2 disabled"
    refute mermaid =~ String.duplicate("a", 100)
  end

  test "node_enabled?/1 só considera desativado o false explícito" do
    assert AdaptiveStudy.node_enabled?(%{"id" => "n1"})
    assert AdaptiveStudy.node_enabled?(%{"enabled" => true})
    assert AdaptiveStudy.node_enabled?(%{"enabled" => nil})
    refute AdaptiveStudy.node_enabled?(%{"enabled" => false})
  end
end
