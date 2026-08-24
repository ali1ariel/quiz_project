defmodule QuizProject.Priorities do
  @moduledoc """
  Gerenciamento pessoal por categorias e itens: cada item trackeia sua própria
  evolução (progresso de leitura, streak de hábito, subtarefas, etc.), e
  adicionar um item novo nunca afeta o progresso dos itens já existentes.

  Autorização de dono é verificada explicitamente aqui (o `actor` é o usuário
  logado); as ações Ash internas rodam com `authorize?: false`.
  """
  use Ash.Domain
  require Ash.Query

  alias QuizProject.AdaptiveStudy
  alias QuizProject.Attempts
  alias QuizProject.Priorities.Activity
  alias QuizProject.Priorities.ActivityTask
  alias QuizProject.Priorities.Category
  alias QuizProject.Priorities.FieldDefinition
  alias QuizProject.Priorities.FieldValue
  alias QuizProject.Priorities.Item
  alias QuizProject.Priorities.ItemCategory
  alias QuizProject.Priorities.ItemLink
  alias QuizProject.Priorities.ItemTag
  alias QuizProject.Priorities.ItemTask
  alias QuizProject.Priorities.Tag

  resources do
    resource Category
    resource Item
    resource ItemTask
    resource Tag
    resource ItemTag
    resource ItemCategory
    resource FieldDefinition
    resource FieldValue
    resource Activity
    resource ActivityTask
    resource ItemLink
  end

  # Autorização

  @doc "Aceita `Category` ou `Item`; `:ok` se `actor` é o dono, `{:error, :unauthorized}` senão."
  def authorize_owner(%{user_id: user_id}, actor) do
    if actor && actor.id == user_id, do: :ok, else: {:error, :unauthorized}
  end

  # Categorias

  @doc "Categorias do usuário, na ordem escolhida por ele."
  def list_categories(%{id: user_id}) do
    Category
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Cria a categoria e o item \"Geral\" que a acompanha (ver `general_item_for_category/1`)."
  def create_category(%{id: user_id}, attrs) do
    position = next_category_position(user_id)

    with {:ok, category} <-
           Category
           |> Ash.Changeset.for_create(
             :create,
             Map.merge(attrs, %{user_id: user_id, position: position}),
             authorize?: false
           )
           |> Ash.create() do
      create_general_item(category)
      {:ok, category}
    end
  end

  def reposition_category(category, position, actor) do
    with :ok <- authorize_owner(category, actor) do
      category
      |> Ash.Changeset.for_update(:reposition, %{position: position}, authorize?: false)
      |> Ash.update()
    end
  end

  def get_category(id, %{id: user_id}) do
    case Ash.get(Category, id, authorize?: false) do
      {:ok, %Category{user_id: ^user_id} = category} -> {:ok, category}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  # Itens

  @doc "Itens ativos (não arquivados) de uma categoria, pela ordem — inclui os que a têm como secundária. Nunca inclui o item \"Geral\"."
  def list_items_by_category(category_id) do
    Item
    |> Ash.Query.filter(
      general == false and is_nil(archived_at) and
        (category_id == ^category_id or exists(secondary_categories, id == ^category_id))
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load([:tags])
    |> Ash.read!(authorize?: false)
  end

  @doc "Itens ativos cuja categoria primária (não secundária) é `category_id`, na ordem — base da reordenação por botões."
  def list_primary_items(category_id) do
    Item
    |> Ash.Query.filter(category_id == ^category_id and is_nil(archived_at) and general == false)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @item_load [
    :tags,
    :secondary_categories,
    :field_values,
    :tasks,
    :category,
    :study_material,
    quiz: [:versions]
  ]

  def get_item(id, %{id: user_id}) do
    case Ash.get(Item, id, authorize?: false, load: @item_load) do
      {:ok, %Item{user_id: ^user_id} = item} -> {:ok, item}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Cria um item validando que `study_material_id`/`quiz_id`, quando presentes,
  pertencem ao próprio usuário — sem essa checagem um item de Prioridades
  poderia apontar para o material de outra pessoa.
  """
  def create_item(%{id: user_id} = user, category, attrs) do
    with :ok <- authorize_owner(category, user),
         :ok <- validate_cross_reference(attrs, user) do
      attrs = maybe_default_title_from_book(attrs, user)
      position = next_item_position(category.id)

      Item
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(attrs, %{user_id: user_id, category_id: category.id, position: position}),
        authorize?: false
      )
      |> Ash.create()
    end
  end

  # Título em branco num item de livro não vira "" na tela — usa o título do
  # próprio livro, como o upload em Conteúdos já faz.
  defp maybe_default_title_from_book(
         %{item_type: :book, study_material_id: material_id} = attrs,
         user
       )
       when not is_nil(material_id) do
    if blank_title?(attrs) do
      case AdaptiveStudy.get_material(material_id, user) do
        {:ok, material} -> Map.put(attrs, :title, material.title)
        _ -> attrs
      end
    else
      attrs
    end
  end

  defp maybe_default_title_from_book(attrs, _user), do: attrs

  defp blank_title?(attrs) do
    case Map.get(attrs, :title) do
      title when is_binary(title) -> String.trim(title) == ""
      _ -> true
    end
  end

  defp validate_cross_reference(%{item_type: :book, study_material_id: material_id}, user)
       when not is_nil(material_id) do
    case AdaptiveStudy.get_material(material_id, user) do
      {:ok, _} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  # Ao contrário de `study_material_id` (biblioteca pessoal, sempre do próprio
  # usuário), um quiz pode pertencer a outra pessoa e ainda assim ser algo que
  # o usuário responde e quer acompanhar — só precisa existir.
  defp validate_cross_reference(%{item_type: :quiz_goal, quiz_id: quiz_id}, _user)
       when not is_nil(quiz_id) do
    case Ash.get(QuizProject.Quizzes.Quiz, quiz_id, authorize?: false) do
      {:ok, _quiz} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp validate_cross_reference(_attrs, _user), do: :ok

  def update_item(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor) do
      item |> Ash.Changeset.for_update(:update, attrs, authorize?: false) |> Ash.update()
    end
  end

  def archive_item(item, actor) do
    with :ok <- authorize_owner(item, actor) do
      item |> Ash.Changeset.for_update(:archive, %{}, authorize?: false) |> Ash.update()
    end
  end

  def unarchive_item(item, actor) do
    with :ok <- authorize_owner(item, actor) do
      item |> Ash.Changeset.for_update(:unarchive, %{}, authorize?: false) |> Ash.update()
    end
  end

  @doc "Exclui o item definitivamente (não é reversível como arquivar/desarquivar)."
  def delete_item(item, actor) do
    with :ok <- authorize_owner(item, actor) do
      Ash.destroy(item, authorize?: false, return_destroyed?: true)
    end
  end

  @doc """
  Troca o `item_type` de um item já existente. Reaproveita
  `validate_cross_reference/2` (a mesma checagem usada na criação) pra
  garantir que `study_material_id`/`quiz_id`, quando presentes no novo tipo,
  continuam pertencendo ao usuário certo.

  Campos do tipo anterior (ex: `habit_current_streak` ao sair de `:habit`)
  não são zerados — ficam no registro, mas `progress_for_item/1` despacha só
  pelo `item_type` atual e os ignora, então não há efeito colateral.
  """
  def change_item_type(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor),
         :ok <- validate_cross_reference(attrs, actor) do
      item
      |> Ash.Changeset.for_update(:change_type, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  def reposition_item(item, position, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:reposition, %{position: position}, authorize?: false)
      |> Ash.update()
    end
  end

  @doc "Define o tier (`S`/`A`/`B`/`C`/`D`) no bloco de prioridades misturadas, ou `nil` pra tirar do board."
  def set_tier(item, tier, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_tier, %{tier: tier}, authorize?: false)
      |> Ash.update()
    end
  end

  def set_course_progress(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_course_progress, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  def set_course_access(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_course_access, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  def set_manual_percent(item, percent, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_manual_percent, %{manual_percent: percent},
        authorize?: false
      )
      |> Ash.update()
    end
  end

  def set_manual_steps(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_manual_steps, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  def set_manual_mode(item, attrs, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:set_manual_mode, attrs, authorize?: false)
      |> Ash.update()
    end
  end

  def check_in_habit(item, actor) do
    with :ok <- authorize_owner(item, actor) do
      item |> Ash.Changeset.for_update(:check_in_habit, %{}, authorize?: false) |> Ash.update()
    end
  end

  # Subtarefas (`:checklist`)

  def list_tasks(item_id) do
    ItemTask
    |> Ash.Query.filter(item_id == ^item_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def create_task(item, title, actor) do
    with :ok <- authorize_owner(item, actor) do
      position = next_task_position(item.id)

      ItemTask
      |> Ash.Changeset.for_create(
        :create,
        %{item_id: item.id, title: title, position: position},
        authorize?: false
      )
      |> Ash.create()
    end
  end

  def toggle_task(task, item, actor) do
    with :ok <- authorize_owner(item, actor) do
      task
      |> Ash.Changeset.for_update(:update, %{done: !task.done}, authorize?: false)
      |> Ash.update()
    end
  end

  # Tags

  def list_tags(%{id: user_id}) do
    Tag
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Cria a tag se ainda não existir, ou devolve a existente com o mesmo nome."
  def find_or_create_tag(%{id: user_id}, name) do
    Tag
    |> Ash.Changeset.for_create(:create, %{user_id: user_id, name: String.trim(name)},
      authorize?: false
    )
    |> Ash.create()
  end

  def add_tag_to_item(item, tag, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:add_tag, %{tag_id: tag.id}, authorize?: false)
      |> Ash.update()
    end
  end

  def remove_tag_from_item(item, tag, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:remove_tag, %{tag_id: tag.id}, authorize?: false)
      |> Ash.update()
    end
  end

  # Categorias secundárias

  def add_secondary_category(item, category, actor) do
    with :ok <- authorize_owner(item, actor),
         :ok <- authorize_owner(category, actor),
         :ok <- reject_primary(item, category) do
      item
      |> Ash.Changeset.for_update(:add_secondary_category, %{category_id: category.id},
        authorize?: false
      )
      |> Ash.update()
    end
  end

  defp reject_primary(%Item{category_id: id}, %Category{id: id}), do: {:error, :is_primary}
  defp reject_primary(_item, _category), do: :ok

  def remove_secondary_category(item, category, actor) do
    with :ok <- authorize_owner(item, actor) do
      item
      |> Ash.Changeset.for_update(:remove_secondary_category, %{category_id: category.id},
        authorize?: false
      )
      |> Ash.update()
    end
  end

  # Campos customizados

  def list_field_definitions(%{id: user_id}) do
    FieldDefinition
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def create_field_definition(%{id: user_id}, attrs) do
    position = next_field_definition_position(user_id)

    FieldDefinition
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{user_id: user_id, position: position}),
      authorize?: false
    )
    |> Ash.create()
  end

  @doc "Grava o valor de um campo customizado no item, no atributo certo pro tipo do campo."
  def set_field_value(item, %FieldDefinition{} = definition, raw_value, actor) do
    with :ok <- authorize_owner(item, actor) do
      attrs =
        %{item_id: item.id, field_definition_id: definition.id}
        |> Map.merge(value_attrs(definition.field_type, raw_value))

      FieldValue
      |> Ash.Changeset.for_create(:upsert, attrs, authorize?: false)
      |> Ash.create()
    end
  end

  defp value_attrs(:number, raw_value) do
    case Float.parse(to_string(raw_value)) do
      {number, _rest} -> %{value_number: number, value_text: nil}
      :error -> %{value_number: nil, value_text: nil}
    end
  end

  defp value_attrs(_text_or_select, raw_value), do: %{value_text: raw_value, value_number: nil}

  # Consultas agregadas

  @tier_order ~w(S A B C D)a

  @doc "Itens ativos com tier definido, agrupados na ordem fixa S > A > B > C > D."
  def list_tiered_items(%{id: user_id}) do
    items =
      Item
      |> Ash.Query.filter(
        user_id == ^user_id and is_nil(archived_at) and not is_nil(tier) and general == false
      )
      |> Ash.Query.load([:tags, :category])
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.tier)

    Enum.map(@tier_order, &{&1, Map.get(items, &1, [])})
  end

  @doc "Itens ativos sem tier definido — candidatos a entrar no bloco de prioridades misturadas. Nunca inclui o item \"Geral\"."
  def list_untiered_items(%{id: user_id}) do
    Item
    |> Ash.Query.filter(
      user_id == ^user_id and is_nil(archived_at) and is_nil(tier) and general == false
    )
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:tags, :category])
    |> Ash.read!(authorize?: false)
  end

  @doc "Filtro flat por categoria (primária ou secundária), tag, tipo e arquivamento. Nunca inclui o item \"Geral\"."
  def filter_items(%{id: user_id}, opts \\ []) do
    query = Ash.Query.filter(Item, user_id == ^user_id and general == false)

    query =
      case Keyword.get(opts, :archived, false) do
        true -> query
        false -> Ash.Query.filter(query, is_nil(archived_at))
      end

    query =
      case Keyword.get(opts, :category_id) do
        nil ->
          query

        category_id ->
          Ash.Query.filter(
            query,
            category_id == ^category_id or exists(secondary_categories, id == ^category_id)
          )
      end

    query =
      case Keyword.get(opts, :tag_id) do
        nil -> query
        tag_id -> Ash.Query.filter(query, exists(tags, id == ^tag_id))
      end

    query =
      case Keyword.get(opts, :item_type) do
        nil -> query
        item_type -> Ash.Query.filter(query, item_type == ^item_type)
      end

    query
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:tags, :category])
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Progresso de um item, no formato certo pro tipo:
  `{:percent, 0..100}` (book/quiz_goal/course/checklist/manual, `nil` quando
  ainda não há como calcular) ou `{:streak, n}` (habit).
  """
  def progress_for_item(%Item{item_type: :book, study_material_id: material_id, user_id: user_id})
      when not is_nil(material_id) do
    %{^material_id => %{total: total, current: current}} =
      AdaptiveStudy.Books.library_progress(user_id, [material_id])

    percent = if total > 0 and current, do: round(current / total * 100), else: nil
    {:percent, percent}
  end

  def progress_for_item(%Item{item_type: :book}), do: {:percent, nil}

  def progress_for_item(%Item{item_type: :quiz_goal, quiz_id: quiz_id, user_id: user_id})
      when not is_nil(quiz_id) do
    case Attempts.best_percent_for_quiz(%{id: user_id}, quiz_id) do
      nil -> {:percent, nil}
      percent -> {:percent, percent |> Decimal.round(0) |> Decimal.to_integer()}
    end
  end

  def progress_for_item(%Item{item_type: :quiz_goal}), do: {:percent, nil}

  def progress_for_item(%Item{
        item_type: :course,
        course_total_steps: total,
        course_completed_steps: current
      }) do
    percent = if total && total > 0, do: round(current / total * 100), else: nil
    {:percent, percent}
  end

  def progress_for_item(%Item{item_type: :habit, habit_current_streak: streak}) do
    {:streak, streak}
  end

  def progress_for_item(%Item{item_type: :checklist} = item) do
    tasks = list_tasks(item.id)
    total = length(tasks)
    done = Enum.count(tasks, & &1.done)

    percent = if total > 0, do: round(done / total * 100), else: nil
    {:percent, percent}
  end

  def progress_for_item(%Item{
        item_type: :manual,
        manual_progress_mode: :steps,
        manual_total_steps: total,
        manual_completed_steps: current
      }) do
    percent = if total && total > 0, do: round(current / total * 100), else: nil
    {:percent, percent}
  end

  def progress_for_item(%Item{item_type: :manual, manual_percent: percent}) do
    {:percent, percent}
  end

  # Atividades

  def list_activities_for_item(item_id, %{id: user_id}) do
    Activity
    |> Ash.Query.filter(item_id == ^item_id and user_id == ^user_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Capturas soltas (sem item) ainda pendentes, mais antiga primeiro — a que mais precisa de atenção."
  def list_loose_captures(%{id: user_id}) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and is_nil(item_id) and status == :pendente)
    |> Ash.Query.sort(logical_date: :asc, position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def count_loose_captures(%{id: user_id}) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and is_nil(item_id) and status == :pendente)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> length()
  end

  @doc "Atividades presas a um item, com `logical_date` de hoje — base das raias da Tela do dia."
  def list_today_activities_by_item(%{id: user_id}) do
    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and not is_nil(item_id) and logical_date == ^Date.utc_today()
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load([:item])
    |> Ash.read!(authorize?: false)
  end

  @doc "Raias da Tela do dia: uma entrada por item com atividade hoje, atividades já separadas por `flow`."
  def list_today_lanes(actor) do
    actor
    |> list_today_activities_by_item()
    # Agrupa pelo id, não pelo struct `%Item{}` em si — instâncias carregadas
    # em `load/1` separadamente podem carregar metadados internos do Ash
    # distintos mesmo representando a mesma linha, o que quebraria `==`.
    |> Enum.group_by(& &1.item.id)
    |> Enum.map(fn {_item_id, [%{item: item} | _] = activities} ->
      %{item: item, activities: Enum.group_by(activities, & &1.flow)}
    end)
    |> Enum.sort_by(& &1.item.title)
  end

  def get_activity(id, %{id: user_id}) do
    case Ash.get(Activity, id, authorize?: false) do
      {:ok, %Activity{user_id: ^user_id} = activity} -> {:ok, activity}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Cria uma atividade presa a um item (checa dono do item) ou uma captura
  solta quando `attrs` não tem `item_id`.
  """
  def create_activity(%{id: user_id} = actor, attrs) do
    with :ok <- validate_item_ownership(attrs, actor) do
      attrs =
        attrs
        |> Map.put_new_lazy(:logical_date, &Date.utc_today/0)
        |> Map.put(:user_id, user_id)

      position = next_activity_position(user_id, Map.get(attrs, :item_id), :todo)

      Activity
      |> Ash.Changeset.for_create(:create, Map.put(attrs, :position, position), authorize?: false)
      |> Ash.create()
    end
  end

  defp validate_item_ownership(%{item_id: item_id}, actor) when not is_nil(item_id) do
    case get_item(item_id, actor) do
      {:ok, _item} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp validate_item_ownership(_attrs, _actor), do: :ok

  def update_activity(activity, attrs, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:update, attrs, authorize?: false) |> Ash.update()
    end
  end

  def reposition_activity(activity, position, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:reposition, %{position: position}, authorize?: false)
      |> Ash.update()
    end
  end

  @doc "Triagem: associa uma captura solta a uma prioridade existente."
  def assign_activity_to_item(activity, item, actor) do
    with :ok <- authorize_owner(activity, actor),
         :ok <- authorize_owner(item, actor) do
      activity
      |> Ash.Changeset.for_update(:assign_item, %{item_id: item.id}, authorize?: false)
      |> Ash.update()
    end
  end

  def start_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:start, %{}, authorize?: false) |> Ash.update()
    end
  end

  def back_to_todo_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:back_to_todo, %{}, authorize?: false) |> Ash.update()
    end
  end

  def complete_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:complete, %{}, authorize?: false) |> Ash.update()
    end
  end

  def mark_activity_not_done(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:mark_not_done, %{}, authorize?: false) |> Ash.update()
    end
  end

  def discard_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity |> Ash.Changeset.for_update(:discard, %{}, authorize?: false) |> Ash.update()
    end
  end

  # Checklist de atividade

  def list_activity_tasks(activity_id) do
    ActivityTask
    |> Ash.Query.filter(activity_id == ^activity_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def create_activity_task(activity, title, actor) do
    with :ok <- authorize_owner(activity, actor) do
      position = next_activity_task_position(activity.id)

      ActivityTask
      |> Ash.Changeset.for_create(
        :create,
        %{activity_id: activity.id, title: title, position: position},
        authorize?: false
      )
      |> Ash.create()
    end
  end

  def toggle_activity_task(task, activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      task
      |> Ash.Changeset.for_update(:update, %{done: !task.done}, authorize?: false)
      |> Ash.update()
    end
  end

  def delete_activity_task(task, activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      Ash.destroy(task, authorize?: false, return_destroyed?: true)
    end
  end

  @doc """
  Sugestões de prioridade pra resolver uma captura solta (triagem em um
  toque): itens cujo título contém o da atividade (case-insensitive); sem
  match, cai pros mais recentes. Nunca sugere o item "Geral" de uma
  categoria — esse caminho é o botão de categoria, à parte.
  """
  def suggest_items_for_activity(%Activity{title: title, user_id: user_id}, limit \\ 4) do
    needle = title |> String.downcase() |> String.trim()

    items =
      Item
      |> Ash.Query.filter(user_id == ^user_id and is_nil(archived_at) and general == false)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(authorize?: false)

    matches =
      if needle == "" do
        []
      else
        Enum.filter(items, &String.contains?(String.downcase(&1.title), needle))
      end

    case matches do
      [] -> Enum.take(items, limit)
      matches -> Enum.take(matches, limit)
    end
  end

  @doc """
  Item "Geral" oculto da categoria, usado pra prender uma atividade solta
  numa categoria sem precisar virar uma prioridade de verdade — nunca
  aparece nas telas de Prioridades (ver filtros `general == false` em
  `list_items_by_category/1` e afins). Categorias criadas antes desta
  função ainda não têm um: criado na primeira vez que for pedido.
  """
  def general_item_for_category(%Category{} = category) do
    Item
    |> Ash.Query.filter(category_id == ^category.id and general == true)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> create_general_item(category)
      item -> item
    end
  end

  defp create_general_item(category) do
    position = next_item_position(category.id)

    {:ok, item} =
      Item
      |> Ash.Changeset.for_create(
        :create,
        %{
          user_id: category.user_id,
          category_id: category.id,
          item_type: :manual,
          title: "#{category.name} - Geral",
          general: true,
          position: position
        },
        authorize?: false
      )
      |> Ash.create()

    item
  end

  # Vínculos entre itens

  @link_direct_labels %{
    parte_de: "é parte de",
    contribui_para: "contribui para",
    relacionado_a: "relacionado a"
  }

  @link_inverse_labels %{
    parte_de: "contém",
    contribui_para: "recebe contribuição de",
    relacionado_a: "relacionado a"
  }

  def create_item_link(item, related_item, link_type, actor) do
    with :ok <- authorize_owner(item, actor),
         :ok <- authorize_owner(related_item, actor) do
      ItemLink
      |> Ash.Changeset.for_create(
        :create,
        %{item_id: item.id, related_item_id: related_item.id, link_type: link_type},
        authorize?: false
      )
      |> Ash.create()
    end
  end

  def delete_item_link(link, item, actor) do
    with :ok <- authorize_owner(item, actor) do
      Ash.destroy(link, authorize?: false, return_destroyed?: true)
    end
  end

  @doc "Vínculos de um item, unindo as duas direções — quem ele aponta e quem aponta pra ele — num formato uniforme."
  def list_item_links(%Item{id: item_id} = item, actor) do
    with :ok <- authorize_owner(item, actor) do
      out_links =
        ItemLink
        |> Ash.Query.filter(item_id == ^item_id)
        |> Ash.Query.load([:related_item])
        |> Ash.read!(authorize?: false)
        |> Enum.map(
          &%{
            link: &1,
            item: &1.related_item,
            link_type: &1.link_type,
            direction: :out,
            label: Map.fetch!(@link_direct_labels, &1.link_type)
          }
        )

      in_links =
        ItemLink
        |> Ash.Query.filter(related_item_id == ^item_id)
        |> Ash.Query.load([:item])
        |> Ash.read!(authorize?: false)
        |> Enum.map(
          &%{
            link: &1,
            item: &1.item,
            link_type: &1.link_type,
            direction: :in,
            label: Map.fetch!(@link_inverse_labels, &1.link_type)
          }
        )

      {:ok, out_links ++ in_links}
    end
  end

  # Posicionamento

  defp next_position_for(query) do
    query
    |> Ash.Query.select([:position])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.position)
    |> case do
      [] -> 0
      positions -> Enum.max(positions) + 1
    end
  end

  defp next_category_position(user_id) do
    Category |> Ash.Query.filter(user_id == ^user_id) |> next_position_for()
  end

  defp next_item_position(category_id) do
    Item |> Ash.Query.filter(category_id == ^category_id) |> next_position_for()
  end

  defp next_task_position(item_id) do
    ItemTask |> Ash.Query.filter(item_id == ^item_id) |> next_position_for()
  end

  defp next_activity_task_position(activity_id) do
    ActivityTask |> Ash.Query.filter(activity_id == ^activity_id) |> next_position_for()
  end

  defp next_field_definition_position(user_id) do
    FieldDefinition |> Ash.Query.filter(user_id == ^user_id) |> next_position_for()
  end

  defp next_activity_position(user_id, nil, flow) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and is_nil(item_id) and flow == ^flow)
    |> next_position_for()
  end

  defp next_activity_position(user_id, item_id, flow) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and item_id == ^item_id and flow == ^flow)
    |> next_position_for()
  end
end
