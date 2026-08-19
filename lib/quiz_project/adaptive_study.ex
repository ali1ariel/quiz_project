defmodule QuizProject.AdaptiveStudy do
  @moduledoc """
  Domínio de Estudo Adaptativo: Ingestão de materiais, curadoria de mapa mental atômico.
  """
  use Ash.Domain

  require Ash.Query

  alias QuizProject.AdaptiveStudy.Block
  alias QuizProject.AdaptiveStudy.Chapter
  alias QuizProject.AdaptiveStudy.Highlight
  alias QuizProject.AdaptiveStudy.NodeBlock
  alias QuizProject.AdaptiveStudy.ReadingPosition
  alias QuizProject.AdaptiveStudy.ReadingPreference
  alias QuizProject.AdaptiveStudy.StudyMaterial

  resources do
    resource StudyMaterial
    resource Chapter
    resource Block
    resource NodeBlock
    resource ReadingPosition
    resource ReadingPreference
    resource Highlight
  end

  @doc "Cria um material de estudo para o usuário."
  def create_material(%{id: user_id}, attrs) when is_map(attrs) do
    attrs =
      case attrs do
        %{raw_content: raw} -> %{attrs | raw_content: strip_frontmatter(raw)}
        _ -> attrs
      end

    attrs = Map.put(attrs, :user_id, user_id)

    StudyMaterial
    |> Ash.Changeset.for_create(:create, attrs, authorize?: false)
    |> Ash.create()
  end

  # Delimitador de abertura na primeira linha e fechamento em "---" ou "..."
  # sozinhos numa linha, como em Jekyll/Pandoc.
  @frontmatter ~r/\A---[ \t]*\r?\n(.*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|\z)/s
  @yaml_key ~r/\A[A-Za-z_][\w.\- ]*:(\s|\z)/

  @doc """
  Remove o bloco de frontmatter YAML da abertura do material.

  Metadados de exportação (`title`, `author`, `source`) não são conteúdo de
  estudo, mas a diretriz de decomposição sem perda obriga a IA a alocá-los em
  algum nó do mapa — e o bloco acaba virando um nó de destaque no lugar do
  primeiro tópico real.

  Um `---` isolado também abre uma linha horizontal em Markdown, então o bloco
  só é removido quando sua primeira linha é de fato uma chave YAML; sem isso o
  texto volta intacto.
  """
  def strip_frontmatter(text) when is_binary(text) do
    case Regex.run(@frontmatter, text) do
      [block, body] ->
        if yaml_frontmatter?(body) do
          text |> String.replace_prefix(block, "") |> String.trim_leading()
        else
          text
        end

      nil ->
        text
    end
  end

  def strip_frontmatter(other), do: other

  defp yaml_frontmatter?(body) do
    body
    |> String.split(~r/\r?\n/)
    |> Enum.find(&(String.trim(&1) != ""))
    |> case do
      nil -> false
      first_line -> Regex.match?(@yaml_key, first_line)
    end
  end

  @doc """
  Materiais de texto do usuário — os que a curadoria de Mapa Mental atende.

  Livro em EPUB fica de fora: ele vive na biblioteca de Conteúdos, que é uma
  tela de leitura, não de curadoria. A ligação entre os dois continua existindo
  no banco, porque a demarcação por capítulo aponta nós de mapa mental para
  blocos do livro.
  """
  def list_materials(%{id: user_id}) do
    StudyMaterial
    |> Ash.Query.filter(user_id == ^user_id and format == :text)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Livros do usuário, do mais recente para o mais antigo."
  def list_books(%{id: user_id}) do
    StudyMaterial
    |> Ash.Query.filter(user_id == ^user_id and format == :epub)
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

  @doc """
  Deleta um material de estudo.

  As imagens do livro vivem em disco, então elas não caem por chave estrangeira
  como o resto: apagá-las é responsabilidade deste ponto, que é por onde toda a
  aplicação remove material.
  """
  def delete_material(material, %{id: user_id}) do
    if material.user_id == user_id do
      case Ash.destroy(material, authorize?: false) do
        :ok ->
          QuizProject.AdaptiveStudy.ImageStore.delete_all(material.id)
          {:ok, material}

        {:ok, result} ->
          QuizProject.AdaptiveStudy.ImageStore.delete_all(material.id)
          {:ok, result}

        error ->
          error
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

    QuizProject.Jobs.run(fn -> curate_material_with_ai(material, user) end)
  end

  @doc """
  Roda a curadoria de IA sobre um material já criado e grava o resultado.

  Extraído de `process_material_async/2` para ser reaproveitado pela curadoria
  de capítulo de livro (`QuizProject.AdaptiveStudy.Books.curate_chapter_async/2`),
  que cria o material e então chama esta função com o mesmo pipeline — mesma
  notificação, mesmo aviso por PubSub. Roda de forma síncrona; quem chama decide
  se isso acontece em background.
  """
  def curate_material_with_ai(material, user, opts \\ []) do
    case QuizProject.AI.curate_mindmap(material.raw_content, opts) do
      {:ok, ai_result, usage} ->
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
              mindmap_tree: %{"nodes" => ensure_root(mindmap, final_title)},
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

        # O uso volta junto porque quem chamou pode querer gravá-lo — a curadoria
        # de capítulo grava; o upload manual ignora.
        {:ok, updated_material, usage}

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

  @doc "Tipos de nó aceitos, na ordem em que devem aparecer para o leitor."
  def node_types, do: @node_types

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

  @doc "Rótulo legível do tipo de um nó."
  def node_type_label("definicao"), do: "Definição"
  def node_type_label("processo"), do: "Processo"
  def node_type_label("exemplo"), do: "Exemplo"
  def node_type_label("dado"), do: "Dado"
  def node_type_label("advertencia"), do: "Advertência"
  def node_type_label(_), do: "Conceito"

  @doc "Rótulo legível de um tipo de relação transversal."
  def relation_label("prerequisito"), do: "pré-requisito"
  def relation_label("aprofunda"), do: "aprofunda"
  def relation_label("contrasta"), do: "contrasta"
  def relation_label("exemplifica"), do: "exemplifica"
  def relation_label("aplica"), do: "aplica"
  def relation_label(_), do: "relacionado"

  @doc """
  Garante um único nó raiz na árvore, criando um quando a IA não entregou.

  O prompt pede que a raiz seja o tema central do material, mas a IA
  frequentemente devolve vários nós de primeiro nível em vez disso. Sem um
  centro, o modo rede não tem de onde irradiar, "voltar à raiz" não tem para
  onde voltar e o sumário abre em várias listas paralelas.

  Uma árvore que já tem raiz única — ou que está vazia — passa intacta, então
  chamar isto duas vezes não empilha raízes.
  """
  def ensure_root(nodes, title) when is_list(nodes) do
    case nodes do
      [] -> []
      [_only_one] -> nodes
      branches -> [synthetic_root(branches, title)]
    end
  end

  def ensure_root(%{"nodes" => nodes}, title) when is_list(nodes),
    do: ensure_root(nodes, title)

  def ensure_root(_nodes, _title), do: []

  @doc """
  Indica se o nó foi criado por `ensure_root/2` em vez de vir da IA.
  """
  def generated_root?(node) when is_map(node), do: Map.get(node, "generated_root") == true
  def generated_root?(_), do: false

  defp synthetic_root(branches, title) do
    %{
      "id" => unused_root_id(branches),
      "label" => root_label(title),
      "description" =>
        "Tema central do material, agrupando os #{length(branches)} blocos de primeiro nível.",
      # Sem conteúdo de propósito: é nó de agrupamento, então não entra na
      # reconstrução do texto (que só concatena folhas).
      "content" => "",
      "order" => 0,
      "node_type" => "conceito",
      "priority" => "high",
      "complexity" => "moderate",
      "user_notes" => "",
      "enabled" => true,
      "generated_root" => true,
      "relations" => [],
      "children" => branches
    }
  end

  defp root_label(title) do
    case String.trim(to_string(title || "")) do
      "" -> "Mapa do material"
      label -> label
    end
  end

  # A IA escolhe os IDs, então "root" pode já estar tomado.
  defp unused_root_id(branches) do
    taken = branches |> flatten_nodes() |> MapSet.new(& &1["id"])

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn
      0 -> "root"
      n -> "root_#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

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
end
