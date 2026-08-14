defmodule QuizProjectWeb.AdaptiveStudyLiveTest do
  use QuizProjectWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuizProject.AdaptiveStudy

  setup :register_and_log_in_user

  test "exige login para acessar o estudo adaptativo", %{} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/study")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/study/new")
  end

  test "exibe lista de materiais e permite criar um novo", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/study")

    assert html =~ "Estudo Adaptativo"
    assert has_element?(view, "#new-study-material-btn")

    # Inicia a criação em /study/new
    {:ok, view_new, _html_new} = live(conn, ~p"/study/new")
    assert has_element?(view_new, "#upload-study-form")

    view_new
    |> form("#upload-study-form", %{
      "title" => "Novo Material Teste",
      "raw_content" => "Este é o conteúdo do material de estudo em Elixir."
    })
    |> render_submit()

    [material] = AdaptiveStudy.list_materials(user)
    assert material.title == "Novo Material Teste"

    # Redireciona para /study/:id/curate
    {:ok, view_curate, html_curate} = live(conn, ~p"/study/#{material.id}/curate")
    assert html_curate =~ "Novo Material Teste"
    assert has_element?(view_curate, "#save-curation-btn")
    assert has_element?(view_curate, "#reconstruct-text-btn")
  end

  test "permite editar nós e adicionar referências cruzadas na curadoria", %{
    conn: conn,
    user: user
  } do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Material Curadoria",
        raw_content: "Conteúdo 1.\n\nConteúdo 2.",
        mindmap_tree: %{
          "nodes" => [
            %{
              "id" => "node_1",
              "label" => "Nó 1",
              "content" => "Conteúdo 1.",
              "priority" => "high",
              "enabled" => true,
              "related_node_ids" => [],
              "children" => []
            },
            %{
              "id" => "node_2",
              "label" => "Nó 2",
              "content" => "Conteúdo 2.",
              "priority" => "medium",
              "enabled" => true,
              "related_node_ids" => [],
              "children" => []
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    # Seleciona o nó 1 e clica em editar
    view |> element("#tree-node-node_1") |> render_click()
    view |> element("#edit-node-btn") |> render_click()

    # Edita os dados do nó
    view
    |> form("#node-edit-form", %{
      "label" => "Nó 1 Editado",
      "content" => "Conteúdo 1 Atualizado.",
      "priority" => "low"
    })
    |> render_submit()

    # Atualiza e salva a curadoria
    view |> element("#save-curation-btn") |> render_click()

    updated = AdaptiveStudy.get_material!(material.id, user)
    assert updated.status == "curated"

    # A árvore veio com dois nós de topo, então ganhou uma raiz sintética: o nó
    # editado não está mais no primeiro nível.
    node_1 = fetch_node(material.id, user, "node_1")
    assert node_1["label"] == "Nó 1 Editado"
    assert node_1["content"] == "Conteúdo 1 Atualizado."
    assert node_1["priority"] == "low"
  end

  test "editar um nó não apaga as anotações pessoais já registradas", %{conn: conn, user: user} do
    {:ok, material} = curated_material(user)
    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    view |> element("#tree-node-node_1") |> render_click()

    view
    |> form("#user-notes-form-node_1", %{"user_notes" => "Revisar antes da prova."})
    |> render_submit()

    view |> element("#edit-node-btn") |> render_click()

    view
    |> form("#node-edit-form", %{"label" => "Nó 1 Editado", "content" => "Conteúdo 1."})
    |> render_submit()

    view |> element("#save-curation-btn") |> render_click()

    node_1 = fetch_node(material.id, user, "node_1")
    assert node_1["label"] == "Nó 1 Editado"
    assert node_1["user_notes"] == "Revisar antes da prova."
  end

  test "desativar um nó o remove do texto reconstruído", %{conn: conn, user: user} do
    {:ok, material} = curated_material(user)
    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    view |> element("#tree-node-node_2") |> render_click()
    view |> element("#toggle-node-enabled-node_2") |> render_click()

    view |> element("#reconstruct-text-btn") |> render_click()
    preview = view |> element(".modal-box") |> render()

    assert preview =~ "Conteúdo 1."
    refute preview =~ "Conteúdo 2."
    assert preview =~ "1 nó(s) marcado(s) como inativo(s) ficaram de fora."
  end

  test "remove referência cruzada pelo painel do nó", %{conn: conn, user: user} do
    {:ok, material} = curated_material(user, node_1_refs: ["node_2"])
    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    view |> element("#tree-node-node_1") |> render_click()
    assert has_element?(view, "#remove-cross-ref-node_1-node_2")

    view |> element("#remove-cross-ref-node_1-node_2") |> render_click()
    view |> element("#save-curation-btn") |> render_click()

    assert fetch_node(material.id, user, "node_1")["related_node_ids"] == []
  end

  describe "detalhamento do nó como modal no telefone" do
    test "abre fechado na carga da página, mesmo com o nó pré-selecionado", %{
      conn: conn,
      user: user
    } do
      {:ok, material} = curated_material(user)
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      # O painel já vem preenchido (é a coluna da direita no desktop), mas sem as
      # classes de modal: no telefone ele fica escondido até o primeiro clique.
      assert has_element?(view, "#node-detail-panel.hidden")
      refute has_element?(view, "#node-detail-panel.fixed")
    end

    test "clicar em um nó sobe a folha e o fechar a derruba", %{conn: conn, user: user} do
      {:ok, material} = curated_material(user)
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      view |> element("#tree-node-node_2") |> render_click()
      assert has_element?(view, "#node-detail-panel.fixed")
      assert render(view) =~ "NÓ ID: node_2"

      view |> element("#close-node-panel-btn") |> render_click()
      refute has_element?(view, "#node-detail-panel")
      assert render(view) =~ "Selecione um nó para visualizar e editar os dados."
    end

    test "editar e anotar não derrubam a folha", %{conn: conn, user: user} do
      {:ok, material} = curated_material(user)
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      view |> element("#tree-node-node_1") |> render_click()

      view
      |> form("#user-notes-form-node_1", %{"user_notes" => "Rever depois."})
      |> render_submit()

      assert has_element?(view, "#node-detail-panel.fixed")

      view |> element("#edit-node-btn") |> render_click()

      view
      |> form("#node-edit-form", %{"label" => "Nó 1", "content" => "Conteúdo 1."})
      |> render_submit()

      assert has_element?(view, "#node-detail-panel.fixed")
    end
  end

  test "sobrevive às mensagens PubSub de tentativas e de mapa mental", %{conn: conn, user: user} do
    {:ok, material} = curated_material(user)
    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    broadcast(user, {:attempt_finished, %{attempt_id: Ecto.UUID.generate()}})
    broadcast(user, {:mindmap_generated, %{material_id: material.id}})

    assert render(view) =~ "Material Curadoria"
  end

  test "carrega o mapa mental ao vivo quando a IA termina o processamento", %{
    conn: conn,
    user: user
  } do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Processando material...",
        raw_content: "Conteúdo bruto."
      })

    {:ok, view, html} = live(conn, ~p"/study/#{material.id}/curate")
    assert html =~ "Mapa Mental ainda não disponível"

    {:ok, _} =
      AdaptiveStudy.update_material(
        material,
        %{
          title: "Material Pronto",
          mindmap_tree: %{
            "nodes" => [
              %{"id" => "node_1", "label" => "Nó Gerado", "content" => "Texto", "children" => []}
            ]
          }
        },
        user
      )

    broadcast(user, {:mindmap_generated, %{material_id: material.id}})

    assert render(view) =~ "Nó Gerado"
    assert has_element?(view, "#tree-node-node_1")
  end

  test "o sumário mostra as conexões transversais pelo rótulo do nó de destino", %{
    conn: conn,
    user: user
  } do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Material Conexões",
        raw_content: "Texto",
        mindmap_tree: %{
          "nodes" => [
            %{
              "id" => "n1",
              "label" => "Nó A",
              "content" => "Texto",
              "relations" => [%{"target_id" => "n2", "type" => "prerequisito"}],
              "children" => [%{"id" => "n2", "label" => "Nó B", "children" => []}]
            }
          ]
        }
      })

    {:ok, view, html} = live(conn, ~p"/study/#{material.id}/curate")

    assert has_element?(view, "#tree-node-n1")
    # A conexão aparece pelo rótulo do alvo, não pelo ID cru: o título traz o
    # tipo da relação e o badge, o rótulo do nó de destino.
    assert html =~ "pré-requisito: Nó B"
    assert has_element?(view, ~s(#tree-node-n1 .badge-secondary), "Nó B")
  end

  test "o sumário mostra prioridade e complexidade lado a lado, cada uma com seu ícone", %{
    conn: conn,
    user: user
  } do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Material Badges",
        raw_content: "Texto",
        mindmap_tree: %{
          "nodes" => [
            %{
              "id" => "n1",
              "label" => "Nó A",
              "content" => "Texto",
              "priority" => "high",
              "complexity" => "complex",
              "children" => []
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

    row = element(view, "#tree-node-n1")
    html = render(row)

    # As duas badges aparecem juntas, cada uma com o ícone que já as distingue
    # no detalhamento do nó (informação = prioridade, capelo = complexidade).
    assert html =~ "Alta"
    assert html =~ "Avançado"
    assert html =~ "hero-information-circle"
    assert html =~ "hero-academic-cap"
  end

  test "material sem raiz gerada pela IA ganha uma na abertura da curadoria", %{
    conn: conn,
    user: user
  } do
    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Compiladores",
        raw_content: "Texto",
        mindmap_tree: %{
          "nodes" => [
            %{"id" => "a", "label" => "Analisador léxico", "children" => []},
            %{"id" => "b", "label" => "Analisador sintático", "children" => []}
          ]
        }
      })

    {:ok, view, html} = live(conn, ~p"/study/#{material.id}/curate")

    # A raiz entra como único nó de primeiro nível, com o título do material.
    assert has_element?(view, "#tree-node-root")
    assert html =~ "Compiladores"
    assert has_element?(view, "#toggle-outline-root")

    # E é gravada ao salvar a curadoria, normalizando o material já existente.
    view |> element("#save-curation-btn") |> render_click()

    saved = AdaptiveStudy.get_material!(material.id, user)
    assert [%{"id" => "root", "generated_root" => true}] = get_in(saved.mindmap_tree, ["nodes"])
  end

  describe "expandir e recolher no sumário" do
    setup %{user: user} do
      {:ok, material} =
        AdaptiveStudy.create_material(user, %{
          title: "Material Ramos",
          raw_content: "Texto",
          mindmap_tree: %{
            "nodes" => [
              %{
                "id" => "n1",
                "label" => "Ramo",
                "children" => [%{"id" => "n1_1", "label" => "Subnó", "children" => []}]
              },
              %{"id" => "n2", "label" => "Folha", "children" => []}
            ]
          }
        })

      %{material: material}
    end

    test "recolher um ramo esconde os subnós e expandir os traz de volta", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      # Árvore pequena começa inteira aberta.
      assert has_element?(view, "#tree-node-n1_1")

      view |> element("#toggle-outline-n1") |> render_click()
      refute has_element?(view, "#tree-node-n1_1")

      view |> element("#toggle-outline-n1") |> render_click()
      assert has_element?(view, "#tree-node-n1_1")
    end

    test "o chevron recolhe sem trocar o nó selecionado", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      view |> element("#tree-node-n2") |> render_click()
      assert render(view) =~ "NÓ ID: n2"

      view |> element("#toggle-outline-n1") |> render_click()

      # O chevron é irmão do bloco clicável justamente para o clique não
      # borbulhar até o `select_node`.
      assert render(view) =~ "NÓ ID: n2"
      refute has_element?(view, "#tree-node-n1_1")
    end

    test "folha não ganha chevron", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      assert has_element?(view, "#toggle-outline-n1")
      refute has_element?(view, "#toggle-outline-n2")
    end

    test "o sumário não repete os controles de recolher tudo do mapa", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      # Recolher e expandir em massa só existem no mapa imersivo; no sumário o
      # chevron de cada ramo dá conta, e a coluna ganhou um header limpo.
      refute has_element?(view, "#outline-collapse-all-btn")
      refute has_element?(view, "#outline-expand-all-btn")
      assert has_element?(view, "#toggle-outline-n1")
    end
  end

  describe "mapa mental em tela cheia" do
    setup %{user: user} do
      {:ok, material} =
        AdaptiveStudy.create_material(user, %{
          title: "Material Mapa",
          raw_content: "Texto",
          mindmap_tree: %{
            "nodes" => [
              %{
                "id" => "root",
                "label" => "Raiz",
                "content" => "",
                "relations" => [
                  %{"target_id" => "b2", "type" => "contrasta", "label" => "caminho oposto"}
                ],
                "children" => [
                  %{
                    "id" => "b1",
                    "label" => "Ramo 1",
                    "content" => "Um.",
                    "children" => [
                      %{
                        "id" => "b1_1",
                        "label" => "Folha",
                        "content" => "Dois.",
                        "children" => []
                      }
                    ]
                  },
                  %{"id" => "b2", "label" => "Ramo 2", "content" => "Três.", "children" => []}
                ]
              }
            ]
          }
        })

      %{material: material}
    end

    test "abre pela curadoria e volta preservando alterações não salvas", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate")

      # altera sem salvar e navega para o mapa
      view |> element("#tree-node-b2") |> render_click()
      view |> element("#toggle-node-enabled-b2") |> render_click()

      view |> element("#open-mindmap-btn") |> render_click()
      assert_patched(view, ~p"/study/#{material.id}/curate/map")
      assert has_element?(view, "#mindmap-canvas")

      # o patch mantém o mesmo processo, então a alteração pendente sobrevive
      view |> element("#exit-mindmap-btn") |> render_click()
      assert_patched(view, ~p"/study/#{material.id}/curate")
      assert render(view) =~ "Alterações não salvas"
    end

    test "abre limpo: só a formação da árvore, sem seleção nem relações", %{
      conn: conn,
      material: material
    } do
      {:ok, view, html} = live(conn, ~p"/study/#{material.id}/curate/map")

      assert has_element?(view, "#map-node-root")
      assert has_element?(view, "#map-node-b1")
      assert has_element?(view, "#map-node-b1_1")

      # nenhuma gaveta cobrindo o mapa e nenhuma relação transversal desenhada
      refute has_element?(view, "#map-drawer-root")
      refute html =~ "caminho oposto"
      refute view |> element("#mindmap-canvas svg") |> render() =~ "stroke-dasharray"

      # o contador da topbar segue mostrando quantas existem
      assert html =~ "conexões transversais"
    end

    test "clicar em um nó revela as relações dele com badge e cor", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-node-root") |> render_click()

      # a curva da relação e seu rótulo entram em cena
      svg = view |> element("#mindmap-canvas svg") |> render()
      assert svg =~ "stroke-dasharray"
      assert svg =~ "caminho oposto"

      # b2 é o alvo da relação: ganha badge e a cor do tipo (contrasta -> error)
      b2 = view |> element("#map-node-b2") |> render()
      assert b2 =~ "contrasta"
      assert b2 =~ "border-error"
      assert b2 =~ "opacity-100"

      # b1 não tem relação com a raiz: some para 20%
      assert view |> element("#map-node-b1") |> render() =~ "opacity-20"
    end

    test "recolhe e expande ramos", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      assert has_element?(view, "#map-node-b1_1")

      view |> element("#map-toggle-b1") |> render_click()
      refute has_element?(view, "#map-node-b1_1")
      assert has_element?(view, "#map-node-b1")

      view |> element("#map-expand-all") |> render_click()
      assert has_element?(view, "#map-node-b1_1")

      view |> element("#map-collapse-all") |> render_click()
      assert has_element?(view, "#map-node-root")
      refute has_element?(view, "#map-node-b1_1")
    end

    test "alterna entre árvore e rede mantendo os mesmos nós", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-radial") |> render_click()
      assert has_element?(view, "#map-node-root")
      assert has_element?(view, "#map-node-b1_1")

      view |> element("#map-mode-tree") |> render_click()
      assert has_element?(view, "#map-node-root")
    end

    test "seleciona um nó no mapa e edita pela gaveta", %{
      conn: conn,
      user: user,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-node-b2") |> render_click()
      assert has_element?(view, "#map-drawer-b2")

      view |> element("#edit-node-btn") |> render_click()

      view
      |> form("#node-edit-form", %{"label" => "Ramo 2 Editado", "content" => "Três."})
      |> render_submit()

      view |> element("#save-curation-btn") |> render_click()

      assert fetch_node(material.id, user, "b2")["label"] == "Ramo 2 Editado"
    end

    test "a gaveta acompanha o nó clicado", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      # o mapa abre sem gaveta
      refute has_element?(view, "#map-drawer-root")

      view |> element("#map-node-b1") |> render_click()
      assert has_element?(view, "#map-drawer-b1")
      refute has_element?(view, "#map-drawer-root")
      assert view |> element("#map-drawer-b1") |> render() =~ "Ramo 1"

      view |> element("#map-node-b2") |> render_click()
      assert has_element?(view, "#map-drawer-b2")
      refute has_element?(view, "#map-drawer-b1")
      assert view |> element("#map-drawer-b2") |> render() =~ "Ramo 2"
    end

    test "realça o nó selecionado e apaga o resto do mapa", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-node-b1") |> render_click()

      # o nó selecionado fica cheio, os demais quase somem
      assert view |> element("#map-node-b1") |> render() =~ "opacity-100"
      assert view |> element("#map-node-b2") |> render() =~ "opacity-20"
      assert view |> element("#map-node-root") |> render() =~ "opacity-20"

      svg = view |> element("#mindmap-canvas svg") |> render()

      # root->b1 toca a seleção e fica cheia; root->b2 e b1_1 caem para 20%
      assert svg =~ "opacity-100"
      assert svg =~ "opacity-20"

      # sem seleção, nada é apagado
      view |> element("#close-node-panel-btn") |> render_click()
      refute view |> element("#mindmap-canvas svg") |> render() =~ "opacity-20"
      refute view |> element("#map-node-b2") |> render() =~ "opacity-20"
    end

    test "Foco aproxima o nó e quem se conecta a ele, e dá para voltar ao mapa", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-node-b1") |> render_click()
      view |> element("#map-mode-focus") |> render_click()

      # b1 no centro, com o pai e o subnó por perto; b2 não se conecta e sai de cena
      assert has_element?(view, "#map-node-b1")
      assert has_element?(view, "#map-node-root")
      assert has_element?(view, "#map-node-b1_1")
      refute has_element?(view, "#map-node-b2")

      # os vizinhos de hierarquia vêm etiquetados
      assert view |> element("#map-node-root") |> render() =~ "nó pai"
      assert view |> element("#map-node-b1_1") |> render() =~ "subnó"

      # voltar para o mapa inteiro preserva a seleção
      view |> element("#map-mode-tree") |> render_click()
      assert has_element?(view, "#map-node-b2")
      assert has_element?(view, "#map-drawer-b1")

      # e dá para voltar ao foco, que recentraliza no selecionado
      view |> element("#map-mode-focus") |> render_click()
      refute has_element?(view, "#map-node-b2")
    end

    test "o foco abre na raiz mesmo sem nada selecionado", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      refute view |> element("#map-mode-focus") |> render() =~ "disabled"
      view |> element("#map-mode-focus") |> render_click()

      # raiz no centro, com os dois ramos ao redor; nada aberto na gaveta
      assert has_element?(view, "#map-node-root")
      assert has_element?(view, "#map-node-b1")
      refute has_element?(view, "#map-node-b1_1")
      refute has_element?(view, "#map-drawer-root")
    end

    test "no foco, clicar abre os detalhes sem mover o mapa", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-focus") |> render_click()
      view |> element("#map-node-b1") |> render_click()

      # a gaveta abre em b1, mas o centro segue sendo a raiz
      assert has_element?(view, "#map-drawer-b1")
      refute has_element?(view, "#map-node-b1_1")
      assert has_element?(view, "#map-node-b2")
    end

    test "explorar recentraliza e marca de onde veio", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-focus") |> render_click()
      # a raiz é o centro, então não tem botão de explorar em si mesma
      refute has_element?(view, "#map-explore-root")

      view |> element("#map-explore-b1") |> render_click()

      # agora o centro é b1: os subnós dele entram e b2 sai de cena
      assert has_element?(view, "#map-node-b1_1")
      refute has_element?(view, "#map-node-b2")

      # a raiz vem marcada como origem, com botão de volta
      assert view |> element("#map-node-root") |> render() =~ "origem"
      assert view |> element("#map-explore-root") |> render() =~ "Voltar para este nó"

      # e voltar por ele funciona
      view |> element("#map-explore-root") |> render_click()
      assert has_element?(view, "#map-node-b2")
      assert view |> element("#map-node-b1") |> render() =~ "origem"
    end

    test "o botão de raiz volta o foco em um salto, de qualquer profundidade", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-focus") |> render_click()
      # centrado na raiz, não há para onde voltar
      refute has_element?(view, "#map-focus-root-btn")

      # dois saltos para longe da raiz
      view |> element("#map-explore-b1") |> render_click()
      view |> element("#map-explore-b1_1") |> render_click()
      assert has_element?(view, "#map-focus-root-btn")

      view |> element("#map-focus-root-btn") |> render_click()

      # de volta ao centro original, com os dois ramos à vista e o neto fora
      assert has_element?(view, "#map-node-b1")
      assert has_element?(view, "#map-node-b2")
      refute has_element?(view, "#map-node-b1_1")

      # e sem trilha de volta pendurada: voltar à raiz recomeça a navegação
      refute view |> element("#map-node-b1") |> render() =~ "origem"
      refute has_element?(view, "#map-focus-root-btn")
    end

    test "no fundo do foco a raiz continua em cena, marcada e explorável", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-focus") |> render_click()
      view |> element("#map-explore-b1") |> render_click()
      view |> element("#map-explore-b1_1") |> render_click()

      # b1_1 é neto da raiz: ela não é vizinha, mas segue disponível
      assert has_element?(view, "#map-node-root")
      assert view |> element("#map-node-root") |> render() =~ "raiz"
      assert has_element?(view, "#map-explore-root")

      # e o clique nela recentraliza
      view |> element("#map-explore-root") |> render_click()
      assert has_element?(view, "#map-node-b2")
    end

    test "o botão de raiz só existe no foco", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      refute has_element?(view, "#map-focus-root-btn")

      view |> element("#map-mode-radial") |> render_click()
      refute has_element?(view, "#map-focus-root-btn")
    end

    test "a legenda traduz só os tipos de nó presentes no mapa", %{
      conn: conn,
      user: user
    } do
      {:ok, material} =
        AdaptiveStudy.create_material(user, %{
          title: "Material Tipos",
          raw_content: "Texto",
          mindmap_tree: %{
            "nodes" => [
              %{
                "id" => "root",
                "label" => "Raiz",
                "node_type" => "conceito",
                "children" => [
                  %{"id" => "d", "label" => "Números", "node_type" => "dado", "children" => []}
                ]
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")
      legend = view |> element("#mindmap-legend") |> render()

      assert legend =~ "Conceito"
      assert legend =~ "Dado"
      assert legend =~ "hero-chart-bar"
      # tipos ausentes do mapa não entram na legenda
      refute legend =~ "Advertência"
      refute legend =~ "Processo"
    end

    test "a bola do cartão carrega cor da prioridade e ícone do tipo", %{
      conn: conn,
      user: user
    } do
      {:ok, material} =
        AdaptiveStudy.create_material(user, %{
          title: "Material Marca",
          raw_content: "Texto",
          mindmap_tree: %{
            "nodes" => [
              %{
                "id" => "root",
                "label" => "Raiz",
                "priority" => "high",
                "node_type" => "dado",
                "children" => []
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")
      card = view |> element("#map-node-root") |> render()

      # cor da prioridade e contraste do texto na mesma marca do ícone do tipo
      assert card =~ "bg-primary"
      assert card =~ "text-primary-content"
      assert card =~ "hero-chart-bar"
      assert card =~ "Prioridade alta · Dado"
    end

    test "o canvas informa o nó de entrada para a abertura da visão", %{
      conn: conn,
      material: material
    } do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      # Sem as coordenadas do nó de entrada o JS não tem como abrir mirando nele
      # e cairia no enquadramento do mapa inteiro.
      canvas = view |> element("#mindmap-canvas") |> render()
      assert canvas =~ "data-entry-x"
      assert canvas =~ "data-entry-y"
    end

    test "fechar a gaveta no foco não desfaz a navegação", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-mode-focus") |> render_click()
      view |> element("#map-explore-b1") |> render_click()
      view |> element("#map-node-b1_1") |> render_click()
      assert has_element?(view, "#map-drawer-b1_1")

      view |> element("#close-node-panel-btn") |> render_click()

      # a gaveta fecha, o centro continua em b1
      refute has_element?(view, "#map-drawer-b1_1")
      assert has_element?(view, "#map-node-b1_1")
      refute has_element?(view, "#map-node-b2")
    end

    test "fecha a gaveta do nó", %{conn: conn, material: material} do
      {:ok, view, _html} = live(conn, ~p"/study/#{material.id}/curate/map")

      view |> element("#map-node-b2") |> render_click()
      assert has_element?(view, "#map-drawer-b2")

      view |> element("#close-node-panel-btn") |> render_click()
      refute has_element?(view, "#map-drawer-b2")
    end
  end

  defp curated_material(user, opts \\ []) do
    AdaptiveStudy.create_material(user, %{
      title: "Material Curadoria",
      raw_content: "Conteúdo 1.\n\nConteúdo 2.",
      mindmap_tree: %{
        "nodes" => [
          %{
            "id" => "node_1",
            "label" => "Nó 1",
            "content" => "Conteúdo 1.",
            "order" => 1,
            "priority" => "high",
            "enabled" => true,
            "related_node_ids" => Keyword.get(opts, :node_1_refs, []),
            "children" => []
          },
          %{
            "id" => "node_2",
            "label" => "Nó 2",
            "content" => "Conteúdo 2.",
            "order" => 2,
            "priority" => "medium",
            "enabled" => true,
            "related_node_ids" => [],
            "children" => []
          }
        ]
      }
    })
  end

  defp fetch_node(material_id, user, node_id) do
    material_id
    |> AdaptiveStudy.get_material!(user)
    |> Map.fetch!(:mindmap_tree)
    |> get_in(["nodes"])
    |> AdaptiveStudy.flatten_nodes()
    |> Enum.find(&(&1["id"] == node_id))
  end

  defp broadcast(user, message) do
    Phoenix.PubSub.broadcast(QuizProject.PubSub, "user:#{user.id}:attempts", message)
    # Garante que a LiveView processou a mensagem antes das asserções.
    :timer.sleep(10)
  end
end
