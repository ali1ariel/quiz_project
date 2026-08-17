defmodule QuizProject.AdaptiveStudy.Highlight do
  @moduledoc """
  Um trecho marcado pelo usuário dentro de um bloco do livro, com nota opcional.

  A posição é o mesmo par bloco + deslocamento de `ReadingPosition`, mas em
  caracteres: `start_offset`/`end_offset` contam dentro do texto plano
  renderizado do bloco (`textContent` no cliente), não dentro do Markdown de
  `Block.content`. É o cliente quem mede os dois lados — seleção e desenho da
  marca — contra a mesma régua, então o deslocamento nunca precisa reconciliar
  com marcação Markdown.

  `quote` guarda uma cópia do trecho selecionado, para a lista de anotações
  poder mostrar o que foi marcado sem recarregar o capítulo inteiro.

  A marcação não atravessa bloco: um parágrafo é a unidade de leitura que a IA
  já demarca (`NodeBlock`) e a busca já indexa, e reaproveitar essa fronteira
  evita reconciliar um intervalo com dois textos diferentes.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  @colors ~w(yellow green blue pink)a

  postgres do
    table "highlights"
    repo QuizProject.Repo

    references do
      reference :material, on_delete: :delete, on_update: :update, index?: false
      reference :chapter, on_delete: :delete, on_update: :update, index?: false
      reference :block, on_delete: :delete, on_update: :update, index?: false
    end

    custom_indexes do
      # Desenhar as marcas de um capítulo: dado o bloco, quais o cobrem.
      index [:block_id]
      # Lista "Minhas anotações" e a limpeza por dono.
      index [:user_id, :material_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :user_id,
        :material_id,
        :chapter_id,
        :block_id,
        :start_offset,
        :end_offset,
        :quote,
        :color,
        :note
      ]
    end

    update :update do
      accept [:note, :color]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    # Duplicado do capítulo/bloco de propósito: a lista "Minhas anotações"
    # varre por livro inteiro, e sem esta coluna cada linha exigiria um join
    # até `chapters` só para filtrar por material.
    attribute :material_id, :uuid do
      allow_nil? false
    end

    attribute :chapter_id, :uuid do
      allow_nil? false
    end

    attribute :block_id, :uuid do
      allow_nil? false
    end

    attribute :start_offset, :integer do
      allow_nil? false
      constraints min: 0
    end

    attribute :end_offset, :integer do
      allow_nil? false
      constraints min: 1
    end

    # Cópia do trecho no momento da marcação. Não é recalculada: reingerir o
    # livro troca os uuid dos blocos e a marcação cai junto (chave estrangeira
    # com `on_delete: :delete`), então não existe um "depois" em que o texto
    # aqui e o do bloco possam divergir.
    attribute :quote, :string do
      allow_nil? false
      constraints trim?: true, allow_empty?: false
    end

    attribute :note, :string do
      constraints trim?: true, allow_empty?: false
    end

    attribute :color, :atom do
      allow_nil? false
      default :yellow
      constraints one_of: @colors
    end

    timestamps()
  end

  relationships do
    belongs_to :material, QuizProject.AdaptiveStudy.StudyMaterial do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end

    belongs_to :chapter, QuizProject.AdaptiveStudy.Chapter do
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

  @doc "Cores disponíveis para marcação."
  def colors, do: @colors
end
