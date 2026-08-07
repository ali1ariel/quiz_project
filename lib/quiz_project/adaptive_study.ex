defmodule QuizProject.AdaptiveStudy do
  @moduledoc """
  Domínio de Estudo Adaptativo: Ingestão de materiais, curadoria de mapa mental atômico.
  """
  use Ash.Domain

  require Ash.Query

  alias QuizProject.AdaptiveStudy.StudyMaterial

  resources do
    resource StudyMaterial
  end

  @doc "Cria um material de estudo para o usuário."
  def create_material(%{id: user_id}, attrs) when is_map(attrs) do
    StudyMaterial
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :user_id, user_id), authorize?: false)
    |> Ash.create()
  end

  @doc "Lista todos os materiais de estudo do usuário."
  def list_materials(%{id: user_id}) do
    StudyMaterial
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Busca um material de estudo por ID pertencente ao usuário."
  def get_material(id, %{id: user_id}) do
    case Ash.get(StudyMaterial, id, authorize?: false) do
      {:ok, %StudyMaterial{user_id: ^user_id} = material} -> {:ok, material}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Busca um material de estudo por ID e lança se não encontrar ou não for do usuário."
  def get_material!(id, %{id: _user_id} = user) do
    case get_material(id, user) do
      {:ok, material} -> material
      {:error, reason} -> raise "Material não encontrado ou não autorizado: #{inspect(reason)}"
    end
  end

  @doc "Atualiza a árvore do Mapa Mental ou dados do material."
  def update_material(material, attrs, %{id: user_id}) do
    if material.user_id == user_id do
      material
      |> Ash.Changeset.for_update(:update, attrs, authorize?: false)
      |> Ash.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Deleta um material de estudo."
  def delete_material(material, %{id: user_id}) do
    if material.user_id == user_id do
      case Ash.destroy(material, authorize?: false) do
        :ok -> {:ok, material}
        {:ok, result} -> {:ok, result}
        error -> error
      end
    else
      {:error, :unauthorized}
    end
  end

  require Logger

  @doc """
  Processa a decomposição do Mapa Mental em background através de `QuizProject.Jobs.run/1`.
  Ao concluir, salva o material, registra a notificação e avisa via PubSub.
  """
  def process_material_async(material, user) do
    Logger.info(
      "[AdaptiveStudy] Iniciando processamento de Mapa Mental em background (Material #{material.id}, Provedor: #{QuizProject.AI.current_provider()})..."
    )

    QuizProject.Jobs.run(fn ->
      case QuizProject.AI.curate_mindmap(material.raw_content) do
        {:ok, ai_result} ->
          suggested_title = Map.get(ai_result, "suggested_title", "Material de Estudo")
          summary = Map.get(ai_result, "summary", "")
          key_concepts = Map.get(ai_result, "key_concepts", [])
          mindmap = Map.get(ai_result, "mindmap", [])

          final_title =
            if material.title != "" and material.title != "Processando material...",
              do: material.title,
              else: suggested_title

          {:ok, updated_material} =
            update_material(
              material,
              %{
                title: final_title,
                summary: summary,
                key_concepts: %{"concepts" => key_concepts},
                mindmap_tree: %{"nodes" => mindmap},
                status: "draft"
              },
              user
            )

          Logger.info(
            "[AdaptiveStudy] Mapa Mental gerado com SUCESSO para o Material #{updated_material.id} (\"#{updated_material.title}\")."
          )

          QuizProject.Notifications.notify_mindmap_generated(updated_material)

          Phoenix.PubSub.broadcast(
            QuizProject.PubSub,
            "user:#{user.id}:attempts",
            {:mindmap_generated, %{material_id: updated_material.id}}
          )

          {:ok, updated_material}

        {:error, reason} ->
          Logger.error(
            "[AdaptiveStudy] ERRO ao gerar Mapa Mental para Material #{material.id}: #{inspect(reason)}"
          )

          QuizProject.Notifications.notify_mindmap_failed(material)

          Phoenix.PubSub.broadcast(
            QuizProject.PubSub,
            "user:#{user.id}:attempts",
            {:mindmap_generated, %{material_id: material.id}}
          )

          {:error, :processing_failed}
      end
    end)
  end

  @doc """
  Reconstrói o texto completo a partir dos nós folhas do mapa mental.
  Percorre os nós em profundidade/ordem e concatena os conteúdos (`content`).

  Nós desativados na curadoria (`"enabled" => false`) e suas subárvores ficam de
  fora, que é o efeito prático do botão Ativo/Inativo da tela de curadoria.
  """
  def reconstruct_raw_text(mindmap_tree) when is_map(mindmap_tree) or is_list(mindmap_tree) do
    mindmap_tree
    |> enabled_leaves()
    |> Enum.sort_by(fn node -> node["order"] || 0 end)
    |> Enum.map(fn node -> String.trim(node["content"] || "") end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def reconstruct_raw_text(_), do: ""

  @doc """
  Indica se o nó participa da reconstrução e das exportações.
  A ausência da chave `"enabled"` significa ativo — só o `false` explícito desativa.
  """
  def node_enabled?(node) when is_map(node), do: Map.get(node, "enabled", true) != false
  def node_enabled?(_), do: false

  defp enabled_leaves(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      children = node["children"] || []

      cond do
        not node_enabled?(node) -> []
        children == [] -> [node]
        true -> enabled_leaves(children)
      end
    end)
  end

  defp enabled_leaves(%{"nodes" => nodes}) when is_list(nodes), do: enabled_leaves(nodes)

  defp enabled_leaves(%{"children" => children}) when is_list(children),
    do: enabled_leaves(children)

  defp enabled_leaves(_), do: []

  @relation_types ~w(prerequisito aprofunda contrasta exemplifica aplica relacionado)
  @node_types ~w(conceito definicao processo exemplo dado advertencia)

  @doc "Tipos de relação transversal aceitos entre nós."
  def relation_types, do: @relation_types

  @doc """
  Relações transversais do nó, sempre no formato
  `%{"target_id" => id, "type" => tipo, "label" => texto}`.

  Aceita tanto o formato atual (`"relations"`) quanto o antigo
  (`"related_node_ids"`, uma lista de IDs sem semântica), porque materiais já
  gravados no banco continuam no formato antigo.
  """
  def node_relations(node) when is_map(node) do
    case Map.get(node, "relations") do
      list when is_list(list) -> Enum.flat_map(list, &normalize_relation/1)
      _ -> Enum.flat_map(Map.get(node, "related_node_ids") || [], &normalize_relation/1)
    end
  end

  def node_relations(_), do: []

  @doc "Tipo do nó usado para forma e cor no mapa; desconhecido vira `\"conceito\"`."
  def node_type(node) when is_map(node) do
    case Map.get(node, "node_type") do
      type when type in @node_types -> type
      _ -> "conceito"
    end
  end

  def node_type(_), do: "conceito"

  defp normalize_relation(target_id) when is_binary(target_id) do
    [%{"target_id" => target_id, "type" => "relacionado", "label" => ""}]
  end

  defp normalize_relation(%{"target_id" => target_id} = relation) when is_binary(target_id) do
    type = Map.get(relation, "type")

    [
      %{
        "target_id" => target_id,
        "type" => if(type in @relation_types, do: type, else: "relacionado"),
        "label" => to_string(Map.get(relation, "label") || "")
      }
    ]
  end

  defp normalize_relation(_), do: []

  @doc "Rótulo legível de um tipo de relação transversal."
  def relation_label("prerequisito"), do: "pré-requisito"
  def relation_label("aprofunda"), do: "aprofunda"
  def relation_label("contrasta"), do: "contrasta"
  def relation_label("exemplifica"), do: "exemplifica"
  def relation_label("aplica"), do: "aplica"
  def relation_label(_), do: "relacionado"

  @doc "Retorna uma lista plana de todos os nós (pais e filhos) do mapa mental."
  def flatten_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      children = node["children"] || []
      [node | flatten_nodes(children)]
    end)
  end

  def flatten_nodes(%{"nodes" => nodes}) when is_list(nodes), do: flatten_nodes(nodes)
  def flatten_nodes(%{"children" => children}) when is_list(children), do: flatten_nodes(children)
  def flatten_nodes(_), do: []

  @empty_mermaid "graph TD\n  empty[\"Nenhum nó disponível\"]"

  @doc """
  Gera uma string no formato de diagrama Mermaid (graph TD) a partir dos nós do mapa mental.
  Inclui a hierarquia entre pais e filhos e as conexões tracejadas de referências cruzadas (`related_node_ids`).

  Referências para IDs inexistentes são descartadas — senão o Mermaid criaria uma
  caixa órfã e sem rótulo para cada ID inválido devolvido pela IA.
  """
  def to_mermaid(nodes) when is_list(nodes) or is_map(nodes) do
    flat = nodes |> flatten_nodes() |> Enum.uniq_by(& &1["id"])

    if flat == [] do
      @empty_mermaid
    else
      known_ids = MapSet.new(flat, & &1["id"])

      node_lines =
        Enum.map(flat, fn node ->
          "  #{sanitize_mermaid_id(node["id"])}[\"#{mermaid_label(node)}\"]"
        end)

      parent_child_lines =
        Enum.flat_map(flat, fn parent ->
          p_id = sanitize_mermaid_id(parent["id"])
          children = parent["children"] || []

          Enum.map(children, fn child ->
            c_id = sanitize_mermaid_id(child["id"])
            "  #{p_id} --> #{c_id}"
          end)
        end)

      cross_ref_lines =
        Enum.flat_map(flat, fn node ->
          src_id = sanitize_mermaid_id(node["id"])

          node
          |> node_relations()
          |> Enum.filter(
            &(MapSet.member?(known_ids, &1["target_id"]) and &1["target_id"] != node["id"])
          )
          |> Enum.map(fn relation ->
            target = sanitize_mermaid_id(relation["target_id"])
            "  #{src_id} -. #{relation_label(relation["type"])} .-> #{target}"
          end)
        end)

      lines =
        ["graph TD"] ++
          node_lines ++ parent_child_lines ++ cross_ref_lines ++ disabled_style(flat)

      Enum.join(lines, "\n")
    end
  end

  def to_mermaid(_), do: @empty_mermaid

  defp disabled_style(flat) do
    case flat |> Enum.reject(&node_enabled?/1) |> Enum.map(&sanitize_mermaid_id(&1["id"])) do
      [] ->
        []

      ids ->
        [
          "  classDef disabled stroke-dasharray:4 3,opacity:0.45",
          "  class #{Enum.join(ids, ",")} disabled"
        ]
    end
  end

  # Rótulos longos viram caixas gigantes que estouram o SVG; aspas quebram a sintaxe.
  defp mermaid_label(node) do
    label =
      (node["label"] || "")
      |> to_string()
      |> String.replace("\"", "'")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    cond do
      label == "" -> "Nó"
      String.length(label) > 60 -> String.slice(label, 0, 59) <> "…"
      true -> label
    end
  end

  defp sanitize_mermaid_id(id) do
    "node_" <> (to_string(id) |> String.replace(~r/[^a-zA-Z0-9_]/, "_"))
  end
end
