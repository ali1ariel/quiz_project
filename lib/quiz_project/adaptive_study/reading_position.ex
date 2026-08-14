defmodule QuizProject.AdaptiveStudy.ReadingPosition do
  @moduledoc """
  Onde o usuário parou em cada livro.

  A posição é bloco mais deslocamento dentro dele, não percentual de rolagem:
  assim ela sobrevive a mudança de fonte, de tamanho e de largura de coluna, que
  é justamente o que o percentual não faz.

  Uma linha por usuário e livro — é o que faz a leitura continuar de outro
  aparelho, no mesmo espírito das tentativas de quiz que já sincronizam.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "reading_positions"
    repo QuizProject.Repo

    references do
      reference :material, on_delete: :delete, on_update: :update, index?: false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      accept [:user_id, :material_id, :chapter_id, :block_position, :offset]

      upsert? true
      upsert_identity :user_material
      upsert_fields [:chapter_id, :block_position, :offset, :updated_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :material_id, :uuid do
      allow_nil? false
    end

    attribute :chapter_id, :uuid do
      allow_nil? false
    end

    # Posição absoluta do bloco no livro, e não o uuid, para a leitura continuar
    # apontando para o mesmo trecho depois de uma reingestão do arquivo.
    attribute :block_position, :integer do
      allow_nil? false
      default 1
    end

    # Fração já rolada dentro do bloco, de 0 a 1.
    attribute :offset, :float do
      allow_nil? false
      default 0.0
    end

    timestamps()
  end

  relationships do
    belongs_to :material, QuizProject.AdaptiveStudy.StudyMaterial do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
    end
  end

  identities do
    identity :user_material, [:user_id, :material_id]
  end
end
