defmodule QuizProject.Priorities.ItemLink do
  @moduledoc """
  Vínculo direcionado e tipado entre dois itens — ex: "este livro
  contribui_para esta matéria". Ortogonal a `ItemCategory` (categoria
  secundária): categoria responde "em que área isso entra", vínculo responde
  "o que isso alimenta/depende".

  Consultar as conexões de um item exige unir as duas direções (quem ele
  aponta e quem aponta pra ele) — ver `QuizProject.Priorities.list_item_links/2`,
  que também resolve o rótulo inverso pro lado de entrada.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_item_links"
    repo QuizProject.Repo

    references do
      reference :item, on_delete: :delete, on_update: :update
      reference :related_item, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:item_id, :related_item_id, :link_type]

      validate fn changeset, _context ->
        item_id = Ash.Changeset.get_attribute(changeset, :item_id)
        related_id = Ash.Changeset.get_attribute(changeset, :related_item_id)

        if item_id && related_id && item_id == related_id do
          {:error, field: :related_item_id, message: "um item não pode se vincular a si mesmo"}
        else
          :ok
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :link_type, :atom do
      allow_nil? false
      constraints one_of: ~w(parte_de contribui_para relacionado_a)a
    end

    timestamps()
  end

  relationships do
    belongs_to :item, QuizProject.Priorities.Item do
      allow_nil? false
    end

    belongs_to :related_item, QuizProject.Priorities.Item do
      allow_nil? false
    end
  end

  identities do
    # Inclui `link_type` na chave: o mesmo par de itens pode ter vínculos de
    # tipos diferentes ao mesmo tempo (ex. `parte_de` e `relacionado_a`); só
    # o mesmo tipo repetido entre o mesmo par é rejeitado.
    identity :item_link, [:item_id, :related_item_id, :link_type]
  end
end
