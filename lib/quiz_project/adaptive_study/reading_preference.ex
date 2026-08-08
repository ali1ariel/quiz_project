defmodule QuizProject.AdaptiveStudy.ReadingPreference do
  @moduledoc """
  Aparência do leitor: fonte, tamanho, entrelinha e largura da coluna.

  É estado do cliente — muda a cada clique e não pertence ao livro — mas fica
  persistido por usuário para acompanhá-lo entre aparelhos. Uma linha por
  usuário, válida para todos os livros.

  O tema (claro/escuro e skin) fica de fora de propósito: já existe em
  `app.css` e vale para a aplicação inteira, não só para o leitor.
  """
  use Ash.Resource,
    domain: QuizProject.AdaptiveStudy,
    data_layer: AshPostgres.DataLayer

  @fonts ~w(serif sans mono)a
  @widths ~w(narrow medium wide)a

  postgres do
    table "reading_preferences"
    repo QuizProject.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      accept [:user_id, :font, :font_size, :line_height, :width]

      upsert? true
      upsert_identity :unique_user
      upsert_fields [:font, :font_size, :line_height, :width, :updated_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :font, :atom do
      allow_nil? false
      default :serif
      constraints one_of: @fonts
    end

    # Multiplicador do corpo do texto. O `.qprose` mede tudo em `em`, então
    # mexer só nisto reescala títulos, listas e código junto.
    attribute :font_size, :integer do
      allow_nil? false
      default 100
      constraints min: 70, max: 200
    end

    # Entrelinha em centésimos, para caber num inteiro: 175 = 1.75.
    attribute :line_height, :integer do
      allow_nil? false
      default 175
      constraints min: 120, max: 240
    end

    attribute :width, :atom do
      allow_nil? false
      default :medium
      constraints one_of: @widths
    end

    timestamps()
  end

  identities do
    identity :unique_user, [:user_id]
  end

  @doc "Fontes disponíveis no leitor."
  def fonts, do: @fonts

  @doc "Larguras de coluna disponíveis."
  def widths, do: @widths
end
