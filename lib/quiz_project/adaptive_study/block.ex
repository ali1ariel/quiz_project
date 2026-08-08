defmodule QuizProject.AdaptiveStudy.Block do
  @moduledoc """
  Unidade indivisível de conteúdo do livro, e a única cópia do texto.

  Nada de texto é guardado fora daqui: nem o `.epub` enviado, nem uma coluna de
  texto corrido paralela. Reconstruir o livro é concatenar `content` na ordem de
  `position` — deixa de ser propriedade a verificar e vira invariante.

  O leitor renderiza blocos, a IA demarca blocos e o filtro seleciona blocos.
  Não existe conversão entre as visões porque não existem duas cópias.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  @types ~w(paragraph heading code list_item quote table figure callout sidebar)a

  postgres do
    table "blocks"
    repo QuizProject.Repo

    references do
      reference :chapter, on_delete: :delete, on_update: :update, index?: false
      reference :material, on_delete: :delete, on_update: :update, index?: false
    end

    custom_indexes do
      # Renderizar o capítulo em ordem.
      index [:chapter_id, :position]
      # Localizar o bloco pela posição absoluta, que é o que a IA referencia.
      index [:material_id, :position], unique: true
      # Busca dentro do livro. `simple` em vez de um idioma fixo porque o
      # material do usuário pode estar em qualquer língua — e livro técnico
      # mistura duas na mesma página.
      index ["to_tsvector('simple', content)"],
        name: "blocks_content_search_index",
        using: "gin"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :material_id,
        :chapter_id,
        :source_id,
        :position,
        :type,
        :lang,
        :caption,
        :content,
        :annotations
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :material_id, :uuid do
      allow_nil? false
    end

    attribute :chapter_id, :uuid do
      allow_nil? false
    end

    # Id que a própria editora já gravou no XHTML (`id="p20"`). Vale mais que um
    # índice gerado por nós: sobrevive a reingestão e as referências cruzadas do
    # livro apontam para ele. Nem todo EPUB traz — quando falta, `position`
    # responde sozinha.
    attribute :source_id, :string

    # Ordem absoluta no livro. É por este número que a IA demarca.
    attribute :position, :integer do
      allow_nil? false
    end

    attribute :type, :atom do
      allow_nil? false
      default :paragraph
      constraints one_of: @types
    end

    attribute :lang, :string

    attribute :caption, :string

    # As duas restrições existem por motivos distintos e igualmente concretos.
    #
    # `trim?: false`: o tipo string do Ash apara espaço nas pontas, e isso comeria
    # a indentação da primeira linha de todo bloco de código — a reconstrução
    # deixaria de ser idêntica ao original, que é a invariante do modelo.
    #
    # `allow_empty?: true`: um `:figure` sem legenda nem texto alternativo é um
    # bloco legítimo e vazio, e `""` viraria nulo, derrubando a ingestão.
    attribute :content, :string do
      allow_nil? false
      default ""
      constraints trim?: false, allow_empty?: true
    end

    # As anotações numeradas da listagem ("#1 Em milímetros") explicam as marcas
    # dentro do código: são conteúdo, não decoração.
    attribute :annotations, {:array, :string} do
      allow_nil? false
      default []
    end
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
  end

  @doc "Tipos de bloco aceitos."
  def types, do: @types

  @doc """
  Conteúdo sem a marcação de bloco, para sumário e resultado de busca.

  O nível do título mora nos `#` do próprio conteúdo, e não numa coluna: o
  bloco já é Markdown e o `.qprose` renderiza a hierarquia sem ajuda.
  """
  def plain_text(content) when is_binary(content) do
    content |> String.replace(~r/\A\#{1,6}\s*/, "") |> String.trim()
  end

  def plain_text(%{content: content}), do: plain_text(content)
end
