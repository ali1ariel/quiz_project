defmodule QuizProject.Priorities.Item do
  @moduledoc """
  Item de Prioridades: uma coisa que o usuário quer trackear a evolução ao
  longo do tempo, dentro de uma categoria.

  Os cinco tipos compartilham identidade (título, categoria, posição,
  arquivamento) numa tabela só — como `AdaptiveStudy.StudyMaterial` já faz
  entre `:text` e `:epub` — e cada tipo usa só as colunas que lhe dizem
  respeito; as demais ficam `nil`. `:book` e `:quiz_goal` não duplicam
  progresso: ele é lido sob demanda de `AdaptiveStudy.Books`/`Attempts`, e só o
  `title` é uma cópia (snapshot na criação), para listar itens sem N+1 nos
  outros domínios.
  """
  use Ash.Resource,
    domain: QuizProject.Priorities,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "priority_items"
    repo QuizProject.Repo

    references do
      reference :user, on_delete: :delete, on_update: :update
      reference :category, on_delete: :delete, on_update: :update
      # Apagar o livro/quiz de origem não apaga nem trava a exclusão: o item
      # de Prioridades vira órfão (mantém título e progresso zerado), em vez
      # de acoplar `Contents`/`Quizzes` ao domínio de Prioridades.
      reference :study_material, on_delete: :nilify, on_update: :update
      reference :quiz, on_delete: :nilify, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :user_id,
        :category_id,
        :item_type,
        :title,
        :notes,
        :position,
        :study_material_id,
        :quiz_id,
        :course_total_steps,
        :course_completed_steps,
        :course_access_link,
        :course_access_login,
        :course_access_password,
        :manual_percent,
        :general,
        :store_points,
        :tier
      ]
    end

    update :update do
      accept [:title, :notes, :store_points]
    end

    # Único jeito de mudar `item_type` depois de criado. As validações
    # condicionais de `study_material_id`/`quiz_id` (bloco `validations`
    # abaixo) já disparam sozinhas pra qualquer action que grave esses
    # atributos, então não precisam ser duplicadas aqui.
    update :change_type do
      accept [
        :item_type,
        :study_material_id,
        :quiz_id,
        :course_total_steps,
        :course_completed_steps
      ]
    end

    update :reposition do
      accept [:position]
    end

    update :archive do
      accept []
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :unarchive do
      accept []
      change set_attribute(:archived_at, nil)
    end

    update :set_tier do
      accept [:tier]
    end

    update :set_course_progress do
      accept [:course_completed_steps, :course_total_steps]
    end

    update :set_course_access do
      accept [:course_access_link, :course_access_login, :course_access_password]
    end

    update :set_manual_percent do
      accept [:manual_percent]
      change set_attribute(:manual_progress_mode, :percent)
    end

    update :set_manual_steps do
      accept [:manual_completed_steps, :manual_total_steps]
      change set_attribute(:manual_progress_mode, :steps)
    end

    update :set_manual_mode do
      accept [:manual_progress_mode, :manual_percent]
    end

    update :add_tag do
      accept []
      require_atomic? false
      argument :tag_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        tag_id = Ash.Changeset.get_argument(changeset, :tag_id)
        Ash.Changeset.manage_relationship(changeset, :tags, [%{id: tag_id}], type: :append)
      end
    end

    update :remove_tag do
      accept []
      require_atomic? false
      argument :tag_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        tag_id = Ash.Changeset.get_argument(changeset, :tag_id)
        Ash.Changeset.manage_relationship(changeset, :tags, [%{id: tag_id}], type: :remove)
      end
    end

    update :add_secondary_category do
      accept []
      require_atomic? false
      argument :category_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        category_id = Ash.Changeset.get_argument(changeset, :category_id)

        Ash.Changeset.manage_relationship(changeset, :secondary_categories, [%{id: category_id}],
          type: :append
        )
      end
    end

    update :remove_secondary_category do
      accept []
      require_atomic? false
      argument :category_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        category_id = Ash.Changeset.get_argument(changeset, :category_id)

        Ash.Changeset.manage_relationship(changeset, :secondary_categories, [%{id: category_id}],
          type: :remove
        )
      end
    end
  end

  validations do
    validate present(:study_material_id),
      where: [attribute_equals(:item_type, :book)],
      message: "obrigatório para itens do tipo livro"

    validate present(:quiz_id),
      where: [attribute_equals(:item_type, :quiz_goal)],
      message: "obrigatório para itens do tipo meta de quiz"
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :category_id, :uuid do
      allow_nil? false
    end

    attribute :item_type, :atom do
      allow_nil? false
      constraints one_of: ~w(book quiz_goal course checklist manual)a
    end

    attribute :title, :string do
      allow_nil? false
      default ""
    end

    attribute :notes, :string do
      default ""
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
    end

    # Item "Geral" criado junto com a categoria, um por categoria, nunca
    # exposto nas telas de Prioridades (Categorias/Ranking/Todos os itens) —
    # existe só pra dar a uma atividade solta um lugar pra prender ("desta
    # categoria", sem precisar virar uma prioridade de verdade). Ver
    # `QuizProject.Priorities.general_item_for_category/1`.
    attribute :general, :boolean do
      allow_nil? false
      default false
    end

    attribute :archived_at, :utc_datetime_usec

    # Escala fixa e compartilhada por todos os itens do usuário, usada pelo
    # bloco de prioridades misturadas. `nil` = fora do board; vários itens
    # podem ocupar o mesmo tier.
    attribute :tier, :atom do
      constraints one_of: ~w(S A B C D)a
    end

    # :book
    attribute :study_material_id, :uuid
    # :quiz_goal
    attribute :quiz_id, :uuid
    # :course
    attribute :course_total_steps, :integer
    attribute :course_completed_steps, :integer, default: 0
    # Credenciais de acesso à plataforma do curso, texto plano — sem
    # criptografia at-rest, porque o usuário precisa recuperar a senha
    # depois, e o projeto não tem infraestrutura de criptografia hoje.
    attribute :course_access_link, :string
    attribute :course_access_login, :string
    attribute :course_access_password, :string
    # :manual
    attribute :manual_percent, :integer do
      default 0
      constraints min: 0, max: 100
    end

    attribute :manual_progress_mode, :atom do
      allow_nil? false
      default :percent
      constraints one_of: ~w(percent steps)a
    end

    attribute :manual_total_steps, :integer
    attribute :manual_completed_steps, :integer, default: 0

    attribute :store_points, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  relationships do
    belongs_to :user, QuizProject.Accounts.User do
      allow_nil? false
    end

    belongs_to :category, QuizProject.Priorities.Category do
      allow_nil? false
    end

    belongs_to :study_material, QuizProject.AdaptiveStudy.StudyMaterial do
      attribute_writable? true
    end

    belongs_to :quiz, QuizProject.Quizzes.Quiz do
      attribute_writable? true
    end

    has_many :tasks, QuizProject.Priorities.ItemTask do
      destination_attribute :item_id
      sort position: :asc
    end

    has_many :field_values, QuizProject.Priorities.FieldValue do
      destination_attribute :item_id
    end

    many_to_many :tags, QuizProject.Priorities.Tag do
      through QuizProject.Priorities.ItemTag
      source_attribute_on_join_resource :item_id
      destination_attribute_on_join_resource :tag_id
    end

    many_to_many :secondary_categories, QuizProject.Priorities.Category do
      through QuizProject.Priorities.ItemCategory
      source_attribute_on_join_resource :item_id
      destination_attribute_on_join_resource :category_id
    end
  end
end
