defmodule QuizProject.Quizzes.Quiz do
  @moduledoc """
  Agrupador de quiz. Versões diferentes são quizzes diferentes internamente,
  mas aparecem para o usuário agrupadas sob este recurso.

  O link público compartilhável aponta para o `public_slug` e sempre serve a
  versão publicada mais recente.
  """
  use Ash.Resource,
    domain: QuizProject.Quizzes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "quizzes"
    repo QuizProject.Repo

    references do
      reference :owner, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept []
      argument :owner_id, :uuid, allow_nil?: false

      change set_attribute(:owner_id, arg(:owner_id))

      change fn changeset, _ ->
        Ash.Changeset.force_change_attribute(changeset, :public_slug, generate_slug())
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :public_slug, :string do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, QuizProject.Accounts.User do
      allow_nil? false
    end

    has_many :versions, QuizProject.Quizzes.QuizVersion do
      sort version_number: :desc
    end
  end

  identities do
    identity :unique_public_slug, [:public_slug]
  end

  defp generate_slug do
    :crypto.strong_rand_bytes(6)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end
end
