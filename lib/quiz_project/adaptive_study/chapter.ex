defmodule QuizProject.AdaptiveStudy.Chapter do
  @moduledoc """
  Capítulo do livro, na ordem que o spine do EPUB declara.

  É a unidade de carregamento do leitor: um livro tem milhares de blocos e a
  tela carrega um capítulo por vez.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "chapters"
    repo QuizProject.Repo

    references do
      reference :material, on_delete: :delete, on_update: :update, index?: true
      reference :curated_material, on_delete: :nilify, on_update: :update, index?: true
    end

    custom_indexes do
      index [:material_id, :position], unique: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :material_id,
        :source_id,
        :href,
        :title,
        :position,
        :level,
        :kind,
        :block_count,
        :estimated_tokens
      ]
    end

    update :update do
      accept [:title, :kind, :block_count, :estimated_tokens]
    end

    # Transição atômica: um único UPDATE...WHERE, então cliques simultâneos no
    # botão de IA nunca disparam dois processamentos do mesmo capítulo.
    update :start_curation do
      accept []
      change set_attribute(:curation_status, :processing)
    end

    update :finish_curation do
      accept [
        :curation_status,
        :curated_material_id,
        :usage_input_tokens,
        :usage_output_tokens,
        :curated_model
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :material_id, :uuid do
      allow_nil? false
    end

    # `idref` do spine. Junto do material identifica o capítulo entre
    # reingestões do mesmo arquivo.
    attribute :source_id, :string do
      allow_nil? false
      default ""
    end

    attribute :href, :string do
      allow_nil? false
      default ""
    end

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :position, :integer do
      allow_nil? false
    end

    attribute :level, :integer do
      allow_nil? false
      default 1
    end

    # `front_matter` | `body` | `back_matter`. Sem isso o leitor abre no aviso
    # de copyright e a IA processa a página de agradecimentos.
    attribute :kind, :atom do
      allow_nil? false
      default :body
      constraints one_of: ~w(front_matter body back_matter)a
    end

    attribute :block_count, :integer do
      allow_nil? false
      default 0
    end

    # Calculado na ingestão porque é determinístico e o sumário precisa dele sem
    # carregar os blocos do capítulo.
    attribute :estimated_tokens, :integer do
      allow_nil? false
      default 0
    end

    # Estado do envio do capítulo para curadoria de IA, pelo botão da barra de
    # leitura. `done` só conta com `curated_material_id` presente — ver
    # `QuizProject.AdaptiveStudy.Books.chapter_ai_state/1`.
    attribute :curation_status, :atom do
      allow_nil? false
      default :none
      constraints one_of: ~w(none processing done failed)a
    end

    # Aponta para o Material de Estudo (texto) gerado a partir deste capítulo.
    # Nula enquanto não processado, ou de novo se o material gerado for apagado.
    attribute :curated_material_id, :uuid

    # Uso real de tokens da curadoria, como o provedor informou — não estimativa.
    # É o que permite `Books.measured_output_ratio/0` corrigir a previsão de
    # custo contra medição em vez de mantê-la calibrada em um caso só.
    #
    # Nulos quando o provedor não informa uso (o Fake, por exemplo) ou quando a
    # curadoria falhou. Nulo e zero significam coisas diferentes aqui.
    attribute :usage_input_tokens, :integer
    attribute :usage_output_tokens, :integer

    # Guardado junto porque a razão entrada/saída depende do modelo: raciocínio
    # ligado e `effort` alto mudam a saída sem mudar o texto devolvido.
    attribute :curated_model, :string

    timestamps()
  end

  relationships do
    belongs_to :material, QuizProject.AdaptiveStudy.StudyMaterial do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end

    belongs_to :curated_material, QuizProject.AdaptiveStudy.StudyMaterial do
      attribute_writable? true
      define_attribute? false
    end

    has_many :blocks, QuizProject.AdaptiveStudy.Block do
      destination_attribute :chapter_id
    end
  end
end
