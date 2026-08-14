defmodule QuizProject.AdaptiveStudy.NodeBlock do
  @moduledoc """
  A demarcação: liga um nó do mapa mental aos blocos que ele cobre.

  É deliberadamente uma tabela de junção, e não uma lista de IDs guardada dentro
  do nó, porque a consulta que o filtro do leitor precisa é a inversa — *dado um
  bloco em tela, que nós o cobrem?* — e essa direção tem que ser indexada.

  Um bloco pode pertencer a mais de um nó: "Retropropagação" e "Treinamento de
  redes" cobrem o mesmo parágrafo em níveis diferentes. É por isso que o nó não
  pode ser a fonte de verdade — concatenar nós duplicaria texto, concatenar
  blocos não.

  `node_id` é string porque o mapa mental vive como JSON em
  `study_materials.mindmap_tree`, e o id do nó é escolhido lá dentro.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "node_blocks"
    repo QuizProject.Repo

    references do
      reference :block, on_delete: :delete, on_update: :update, index?: false
      reference :material, on_delete: :delete, on_update: :update, index?: false
    end

    custom_indexes do
      # Filtro: dado o bloco, quem o cobre.
      index [:block_id]
      # Curadoria: dado o nó, que texto é.
      index [:material_id, :node_id]
      index [:material_id, :node_id, :block_id], unique: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:material_id, :node_id, :block_id, :confidence]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :material_id, :uuid do
      allow_nil? false
    end

    attribute :node_id, :string do
      allow_nil? false
    end

    attribute :block_id, :uuid do
      allow_nil? false
    end

    # Quanto a IA se compromete com esta demarcação. O filtro pode usar para
    # ordenar ocorrências sem precisar de outra tabela.
    attribute :confidence, :decimal do
      allow_nil? false
      default Decimal.new("1.0")
    end

    timestamps()
  end

  relationships do
    belongs_to :material, QuizProject.AdaptiveStudy.StudyMaterial do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end

    belongs_to :block, QuizProject.AdaptiveStudy.Block do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end
  end
end
