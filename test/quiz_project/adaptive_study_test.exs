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

  describe "ensure_root/2" do
    test "agrupa vários nós de primeiro nível sob uma raiz com o título do material" do
      nodes = [
        %{"id" => "a", "label" => "Bloco A", "children" => []},
        %{"id" => "b", "label" => "Bloco B", "children" => []}
      ]

      assert [root] = AdaptiveStudy.ensure_root(nodes, "Compiladores")

      assert root["label"] == "Compiladores"
      assert root["content"] == ""
      assert AdaptiveStudy.generated_root?(root)
      assert Enum.map(root["children"], & &1["id"]) == ["a", "b"]
    end

    test "deixa intacta a árvore que já tem raiz única" do
      nodes = [
        %{
          "id" => "raiz",
          "label" => "Tema",
          "children" => [%{"id" => "a", "label" => "A", "children" => []}]
        }
      ]

      assert AdaptiveStudy.ensure_root(nodes, "Outro título") == nodes
    end

    test "é idempotente: chamar duas vezes não empilha raízes" do
      nodes = [
        %{"id" => "a", "label" => "A", "children" => []},
        %{"id" => "b", "label" => "B", "children" => []}
      ]

      once = AdaptiveStudy.ensure_root(nodes, "Título")
      assert AdaptiveStudy.ensure_root(once, "Título") == once
    end

    test "não colide com um ID 'root' que a IA já tenha usado" do
      nodes = [
        %{"id" => "root", "label" => "A", "children" => []},
        %{"id" => "root_1", "label" => "B", "children" => []}
      ]

      assert [%{"id" => id}] = AdaptiveStudy.ensure_root(nodes, "Título")
      refute id in ["root", "root_1"]
    end

    test "árvore vazia continua vazia" do
      assert AdaptiveStudy.ensure_root([], "Título") == []
    end

    test "título em branco vira um rótulo genérico em vez de raiz sem nome" do
      nodes = [
        %{"id" => "a", "label" => "A", "children" => []},
        %{"id" => "b", "label" => "B", "children" => []}
      ]

      assert [%{"label" => "Mapa do material"}] = AdaptiveStudy.ensure_root(nodes, "   ")
      assert [%{"label" => "Mapa do material"}] = AdaptiveStudy.ensure_root(nodes, nil)
    end

    test "a raiz criada não entra na reconstrução do texto" do
      nodes = [
        %{"id" => "a", "label" => "A", "content" => "Um.", "order" => 1, "children" => []},
        %{"id" => "b", "label" => "B", "content" => "Dois.", "order" => 2, "children" => []}
      ]

      with_root = AdaptiveStudy.ensure_root(nodes, "Título")

      assert AdaptiveStudy.reconstruct_raw_text(%{"nodes" => with_root}) ==
               AdaptiveStudy.reconstruct_raw_text(%{"nodes" => nodes})
    end
  end

  describe "strip_frontmatter/1" do
    test "remove o bloco de metadados da abertura" do
      text = """
      ---
      title: "Deep Learning with Python, Third Edition"
      author: "François Chollet"
      source: "livro.epub"
      ---

      # 1 What is deep learning?

      Over the past decade...
      """

      assert AdaptiveStudy.strip_frontmatter(text) ==
               "# 1 What is deep learning?\n\nOver the past decade...\n"
    end

    test "aceita fechamento com reticências e sem linha final" do
      assert AdaptiveStudy.strip_frontmatter("---\ntitle: X\n...") == ""
    end

    test "preserva linha horizontal de Markdown no início do texto" do
      text = "---\n\nTexto que abre com uma régua horizontal.\n\n---\n\nResto."
      assert AdaptiveStudy.strip_frontmatter(text) == text
    end

    test "preserva o texto quando o bloco não é fechado" do
      text = "---\ntitle: X\nautor: Y\n\nO capítulo começa aqui sem fechar o bloco."
      assert AdaptiveStudy.strip_frontmatter(text) == text
    end

    test "só remove na abertura, não no meio do material" do
      text = "Introdução.\n\n---\ntitle: X\n---\n\nFim."
      assert AdaptiveStudy.strip_frontmatter(text) == text
    end

    test "devolve entradas que não são texto sem alteração" do
      assert AdaptiveStudy.strip_frontmatter(nil) == nil
      assert AdaptiveStudy.strip_frontmatter("") == ""
    end
  end

  test "create_material/2 grava o material já sem o frontmatter", %{user: user} do
    assert {:ok, material} =
             AdaptiveStudy.create_material(user, %{
               title: "Livro",
               raw_content: "---\ntitle: Livro\nsource: livro.epub\n---\n\nPrimeiro parágrafo."
             })

    assert material.raw_content == "Primeiro parágrafo."
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

  test "node_enabled?/1 só considera desativado o false explícito" do
    assert AdaptiveStudy.node_enabled?(%{"id" => "n1"})
    assert AdaptiveStudy.node_enabled?(%{"enabled" => true})
    assert AdaptiveStudy.node_enabled?(%{"enabled" => nil})
    refute AdaptiveStudy.node_enabled?(%{"enabled" => false})
  end
end
