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
  require Logger

  alias QuizProject.AdaptiveStudy
  alias QuizProject.Attempts
  alias QuizProject.Priorities.Activity
  alias QuizProject.Priorities.ActivityTask
  alias QuizProject.Priorities.Category
  alias QuizProject.Priorities.Clock
  alias QuizProject.Priorities.FieldDefinition
  alias QuizProject.Priorities.FieldValue
  alias QuizProject.Priorities.Habit
  alias QuizProject.Priorities.HabitOverride
  alias QuizProject.Priorities.HabitRecurrence
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
    resource Habit
    resource HabitOverride
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

  # Hábito deixou de ser um `item_type` de `Item` (Fase 4 — virou seu
  # próprio resource, `Priorities.Habit`) e o schema não aceita mais criar
  # um novo item assim. Uma linha `item_type: "habit"` que sobreviva de
  # antes dessa migração (produção, principalmente — bancos de dev/teste
  # não têm esse legado) derruba qualquer despacho por tipo
  # (`progress_for_item/1`, `Components.item_type_label/1`, o `type_editor/1`
  # do `ItemModal`, ...) com `FunctionClauseError`. Em vez de blindar cada
  # função de despacho separadamente, todo ponto que lista ou busca um
  # `Item` passa primeiro por aqui: encontrar um desses apaga o registro
  # (cascade normal de `Item`) e ele nunca chega a ser renderizado —
  # self-healing, sem precisar de migração de dados manual.
  defp prune_legacy_habit_items(items) when is_list(items) do
    {legacy, valid} = Enum.split_with(items, &(&1.item_type == :habit))
    Enum.each(legacy, &delete_legacy_habit_item/1)
    valid
  end

  defp prune_legacy_habit_items(%Item{item_type: :habit} = item) do
    delete_legacy_habit_item(item)
    nil
  end

  defp prune_legacy_habit_items(item_or_nil), do: item_or_nil

  defp delete_legacy_habit_item(item) do
    Logger.warning(
      "Removendo item legado item_type: :habit (id=#{item.id}, title=#{inspect(item.title)}) — " <>
        "hábito virou Priorities.Habit, esse tipo não existe mais em Item."
    )

    Ash.destroy(item, authorize?: false)
  end

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
    |> prune_legacy_habit_items()
  end

  @doc "Itens ativos cuja categoria primária (não secundária) é `category_id`, na ordem — base da reordenação por botões."
  def list_primary_items(category_id) do
    Item
    |> Ash.Query.filter(category_id == ^category_id and is_nil(archived_at) and general == false)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
    |> prune_legacy_habit_items()
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
      {:ok, %Item{user_id: ^user_id, item_type: :habit} = item} ->
        prune_legacy_habit_items(item)
        {:error, :not_found}

      {:ok, %Item{user_id: ^user_id} = item} ->
        {:ok, item}

      {:ok, _} ->
        {:error, :unauthorized}

      error ->
        error
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

  Campos do tipo anterior (ex: `manual_percent` ao sair de `:manual`) não são
  zerados — ficam no registro, mas `progress_for_item/1` despacha só pelo
  `item_type` atual e os ignora, então não há efeito colateral.
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
      |> prune_legacy_habit_items()
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
    |> prune_legacy_habit_items()
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
    |> prune_legacy_habit_items()
  end

  @doc """
  Progresso de um item, no formato certo pro tipo: sempre
  `{:percent, 0..100}` (`nil` quando ainda não há como calcular) — hábito
  não é mais um `item_type` de `Item` (ver `Priorities.Habit`), então não
  existe mais clause `{:streak, n}` aqui.
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
    |> Ash.Query.filter(
      user_id == ^user_id and is_nil(item_id) and is_nil(habit_id) and status == :pendente
    )
    |> Ash.Query.sort(logical_date: :asc, position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def count_loose_captures(%{id: user_id}) do
    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and is_nil(item_id) and is_nil(habit_id) and status == :pendente
    )
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> length()
  end

  @doc """
  Base do board da Tela do dia: instância de hábito devida hoje (qualquer
  `flow` — é o hábito que expira por dia, não o resto), atividade presa a
  item ainda aberta e não adiada pra depois de hoje (não expira mais
  sozinha, fica até ser resolvida, não importa a `logical_date` — ver
  `snooze_activity/3`) e qualquer atividade (presa a item ou captura solta)
  resolvida hoje — pra "Feito" continuar sendo um recorte diário em vez de
  acumular pra sempre. Uma captura solta ainda `:pendente` só aparece em
  "Capturas soltas" (ver `list_loose_captures/1`).
  """
  def list_today_activities(%{id: user_id}) do
    today = Clock.today()

    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and
        ((not is_nil(habit_id) and logical_date == ^today) or
           (is_nil(habit_id) and not is_nil(item_id) and flow != :feito and
              (is_nil(snoozed_until) or snoozed_until <= ^today)) or
           (is_nil(habit_id) and flow == :feito and resolved_date == ^today))
    )
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(item: [:category], habit: [item: [:category]])
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Atividades entre `from_date` e `to_date` (inclusive) — hábito pelo dia
  devido (`logical_date`), o resto pelo dia em que foi resolvido
  (`resolved_date`). Base do calendário de Histórico (`KanbanLive.History`);
  uma consulta cobre o mês inteiro, agrupamento por dia fica por conta de
  quem chama.
  """
  def list_activities_between(%{id: user_id}, from_date, to_date) do
    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and
        ((not is_nil(habit_id) and logical_date >= ^from_date and logical_date <= ^to_date) or
           (is_nil(habit_id) and flow == :feito and resolved_date >= ^from_date and
              resolved_date <= ^to_date))
    )
    |> Ash.Query.load(item: [:category], habit: [item: [:category]])
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Atividades presas a um item ou hábito hoje, agrupadas só por `flow` — um
  board único pro dia (3 colunas: a fazer/fazendo/feito), sem raia por
  prioridade. O que diferencia um card do outro na tela é a cor lateral e a
  badge da categoria (ver `Components.activity_card/1`), não mais o
  agrupamento em si.
  """
  def list_today_activities_by_flow(actor) do
    Enum.group_by(list_today_activities(actor), & &1.flow)
  end

  @doc """
  Atividades pendentes com `logical_date` a partir de `from` (inclusive) —
  usado só pelo backfill inicial de `QuizProject.GoogleCalendar.connect/2`,
  pra popular o calendário recém-criado sem inundá-lo de histórico já
  resolvido.
  """
  def list_pending_activities_from(%{id: user_id}, from) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and status == :pendente and logical_date >= ^from)
    |> Ash.read!(authorize?: false)
  end

  def get_activity(id, %{id: user_id}) do
    case Ash.get(Activity, id, authorize?: false, load: [:habit]) do
      {:ok, %Activity{user_id: ^user_id} = activity} -> {:ok, activity}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Busca a atividade vinculada a um evento do Google pelo id do evento (sync de entrada)."
  def get_activity_by_google_event_id(google_event_id) do
    Activity
    |> Ash.Query.filter(google_event_id == ^google_event_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, activity} -> {:ok, activity}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Cria uma atividade presa a um item (checa dono do item), instância de um
  hábito (checa dono do hábito) ou uma captura solta quando `attrs` não tem
  nenhum dos dois.
  """
  def create_activity(%{id: user_id} = actor, attrs) do
    with :ok <- validate_item_ownership(attrs, actor),
         :ok <- validate_habit_ownership(attrs, actor) do
      attrs =
        attrs
        |> Map.put_new_lazy(:logical_date, &Clock.today/0)
        |> Map.put(:user_id, user_id)

      position =
        next_activity_position(
          user_id,
          Map.get(attrs, :item_id),
          Map.get(attrs, :habit_id),
          :todo
        )

      Activity
      |> Ash.Changeset.for_create(:create, Map.put(attrs, :position, position), authorize?: false)
      |> Ash.create()
      |> sync_google_out(:insert)
    end
  end

  @doc """
  Cria uma atividade a partir de um evento adicionado manualmente no
  calendário dedicado do usuário (sync de entrada, ver
  `QuizProject.GoogleCalendar.reconcile/1`) — nasce como captura solta, já
  vinculada ao evento. Não passa por `sync_google_out`: o evento já existe
  do lado do Google, não há nada nesta criação que precise ser escrito lá.
  """
  def create_activity_from_google(%{id: user_id}, attrs) do
    position = next_activity_position(user_id, nil, nil, :todo)

    Activity
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{user_id: user_id, position: position}),
      authorize?: false
    )
    |> Ash.create()
  end

  defp validate_item_ownership(%{item_id: item_id}, actor) when not is_nil(item_id) do
    case get_item(item_id, actor) do
      {:ok, _item} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp validate_item_ownership(_attrs, _actor), do: :ok

  defp validate_habit_ownership(%{habit_id: habit_id}, actor) when not is_nil(habit_id) do
    case get_habit(habit_id, actor) do
      {:ok, _habit} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp validate_habit_ownership(_attrs, _actor), do: :ok

  def update_activity(activity, attrs, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:update, attrs, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
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
      activity
      |> Ash.Changeset.for_update(:complete, %{}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  def mark_activity_not_done(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:mark_not_done, %{}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  def discard_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:discard, %{}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  @doc "Desfaz a resolução de uma atividade (concluída, não cumprida ou descartada por engano) — volta pra \"a fazer\"."
  def reopen_activity(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:reopen, %{}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  @doc "Corrige o desfecho (concluída/não cumprida) de uma atividade já resolvida, sem reabri-la nem mudar seu dia — só o Histórico usa isto."
  def correct_activity_status(activity, status, actor)
      when status in [:concluida, :nao_cumprida] do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:correct_status, %{status: status}, authorize?: false)
      |> Ash.update()
    end
  end

  @doc "Adia uma atividade presa a item: some da Tela do dia até `until` (que precisa ser depois de hoje)."
  def snooze_activity(activity, until, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:snooze, %{until: until}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  @doc "Cancela o adiamento de uma atividade antes da data — volta a aparecer na Tela do dia."
  def clear_activity_snooze(activity, actor) do
    with :ok <- authorize_owner(activity, actor) do
      activity
      |> Ash.Changeset.for_update(:clear_snooze, %{}, authorize?: false)
      |> Ash.update()
      |> sync_google_out(:patch)
    end
  end

  @doc "Grava o evento do Google criado/atualizado a partir desta atividade (sync de saída, ver `QuizProject.GoogleCalendar`)."
  def link_google_event(%Activity{} = activity, google_event_id, google_updated_at) do
    activity
    |> Ash.Changeset.for_update(
      :link_google_event,
      %{google_event_id: google_event_id, google_updated_at: google_updated_at},
      authorize?: false
    )
    |> Ash.update()
  end

  @doc """
  Desfaz o vínculo com um evento do Google cancelado/apagado (sync de
  entrada) — não mexe em `status`/`flow`: cancelar no Google não é uma
  resolução de negócio, só para de espelhar.
  """
  def unlink_google_event(%Activity{} = activity) do
    activity
    |> Ash.Changeset.for_update(:unlink_google_event, %{}, authorize?: false)
    |> Ash.update()
  end

  @doc """
  Aplica uma edição feita direto no Google Calendar (sync de entrada, ver
  `QuizProject.GoogleCalendar.reconcile/1`). Não passa por
  `sync_google_out`: escrever de volta o que acabou de chegar do Google
  criaria um ping-pong entre app e Google.
  """
  def sync_activity_from_google(%Activity{} = activity, attrs) do
    activity
    |> Ash.Changeset.for_update(:sync_from_google, attrs, authorize?: false)
    |> Ash.update()
  end

  # Dispara a sincronização de saída com o Google Calendar em background,
  # depois de qualquer mutação com efeito visível no calendário — sem
  # conexão do usuário é no-op (checado dentro do próprio
  # `GoogleCalendar.sync_out_*`, não aqui). `correct_activity_status/3` fica
  # de fora dos call sites: é correção só de Histórico, não muda nada que o
  # Google precise saber.
  defp sync_google_out({:ok, %Activity{} = activity} = result, kind) do
    QuizProject.Jobs.run(fn -> do_sync_google_out(activity, kind) end)
    result
  end

  defp sync_google_out(result, _kind), do: result

  defp do_sync_google_out(activity, :insert),
    do: QuizProject.GoogleCalendar.sync_out_create(activity)

  defp do_sync_google_out(activity, :patch),
    do: QuizProject.GoogleCalendar.sync_out_update(activity)

  @doc "Limpa `snoozed_until` de atividades cujo adiamento já venceu — chamado no mount da Tela do dia, mesma lógica de auto-limpeza de `close_overdue_habit_instances/2`."
  def clear_expired_snoozes(%{id: user_id}) do
    today = Clock.today()

    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and not is_nil(snoozed_until) and snoozed_until <= ^today
    )
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn activity ->
      activity |> Ash.Changeset.for_update(:clear_snooze, %{}, authorize?: false) |> Ash.update()
    end)
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
  Todas as prioridades ativas do usuário, incluindo o item "Geral" de cada
  categoria — base do dropdown "Anexar" (categoria escolhida primeiro,
  depois a lista de prioridades daquela categoria, ver
  `Components.attach_item_options/2`). Ordenado com o "Geral" primeiro
  dentro de cada categoria.
  """
  def list_items_including_general(%{id: user_id}) do
    Item
    |> Ash.Query.filter(user_id == ^user_id and is_nil(archived_at))
    |> Ash.Query.sort(general: :desc, title: :asc)
    |> Ash.read!(authorize?: false)
    |> prune_legacy_habit_items()
  end

  @doc "Resolve o `item_id` escolhido no dropdown \"Anexar\" num `Item` — vazio/`nil` é \"fica solta\" (só válido pra atividade comum; hábito exige uma escolha)."
  def resolve_attach_item(nil, _actor), do: {:ok, nil}
  def resolve_attach_item("", _actor), do: {:ok, nil}
  def resolve_attach_item(item_id, actor), do: get_item(item_id, actor)

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

  # Hábitos

  @doc "Cria um hábito — nasce `:daily` por padrão; `item_id` é obrigatório (hábito é sempre extensão de uma prioridade)."
  def create_habit(%{id: user_id} = user, attrs) do
    with :ok <- authorize_habit_item(attrs, user) do
      Habit
      |> Ash.Changeset.for_create(:create, Map.put(attrs, :user_id, user_id), authorize?: false)
      |> Ash.create()
    end
  end

  defp authorize_habit_item(%{item_id: item_id}, user) when not is_nil(item_id) do
    case get_item(item_id, user) do
      {:ok, _item} -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_habit_item(_attrs, _user), do: {:error, :unauthorized}

  def get_habit(id, %{id: user_id}) do
    case Ash.get(Habit, id, authorize?: false) do
      {:ok, %Habit{user_id: ^user_id} = habit} -> {:ok, habit}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  def set_habit_frequency(habit, attrs, actor) do
    with :ok <- authorize_owner(habit, actor) do
      habit |> Ash.Changeset.for_update(:update, attrs, authorize?: false) |> Ash.update()
    end
  end

  @doc """
  Mudança de frequência com escopo "essa [data] e as próximas": o hábito
  atual é encerrado no dia anterior a `date` (`ends_on`), e nasce um hábito
  novo com a regra de `attrs`, valendo a partir de `date` (`starts_on`) —
  os dias antes de `date` continuam com a regra antiga (já vale pros dias
  já passados, que são `Activity`s independentes, e pros dias entre hoje e
  `date` na prévia de "Próximos dias"). Pra mudar a regra inteira, sem esse
  corte, usar `set_habit_frequency/3`.
  """
  def change_habit_frequency_from(habit, date, attrs, actor) do
    with :ok <- authorize_owner(habit, actor),
         {:ok, _ended} <-
           habit
           |> Ash.Changeset.for_update(:update, %{ends_on: Date.add(date, -1)}, authorize?: false)
           |> Ash.update() do
      Habit
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(attrs, %{
          user_id: habit.user_id,
          item_id: habit.item_id,
          title: habit.title,
          starts_on: date
        }),
        authorize?: false
      )
      |> Ash.create()
    end
  end

  def get_habit_occurrence_override(habit_id, date) do
    HabitOverride
    |> Ash.Query.filter(habit_id == ^habit_id and date == ^date)
    |> Ash.read_one!(authorize?: false)
  end

  @doc "Cria ou atualiza a exceção do hábito pra `date` (\"pular esse dia\" e/ou título/nota só daquele dia) — não mexe na regra nem nos outros dias."
  def set_habit_occurrence_override(habit, date, attrs, actor) do
    with :ok <- authorize_owner(habit, actor) do
      HabitOverride
      |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{habit_id: habit.id, date: date}),
        authorize?: false
      )
      |> Ash.create()
    end
  end

  @doc "Remove a exceção do hábito pra `date`, se existir — volta a valer a regra normal nesse dia."
  def clear_habit_occurrence_override(habit, date, actor) do
    with :ok <- authorize_owner(habit, actor) do
      case get_habit_occurrence_override(habit.id, date) do
        nil -> :ok
        override -> Ash.destroy(override, authorize?: false)
      end
    end
  end

  @doc "Se o hábito é devido em `date`, já considerando exceção de \"pular esse dia\" — ver `HabitRecurrence.due_on?/3`."
  def habit_due_on?(habit, date) do
    case get_habit_occurrence_override(habit.id, date) do
      %{skipped: true} -> false
      _ -> HabitRecurrence.due_on?(habit, date)
    end
  end

  @doc "Título efetivo do hábito em `date` — o da exceção, se houver um não-vazio; senão o do próprio hábito."
  def occurrence_title(habit, date) do
    case get_habit_occurrence_override(habit.id, date) do
      %{title: title} when is_binary(title) and title != "" -> title
      _ -> habit.title
    end
  end

  def archive_habit(habit, actor) do
    with :ok <- authorize_owner(habit, actor) do
      habit |> Ash.Changeset.for_update(:archive, %{}, authorize?: false) |> Ash.update()
    end
  end

  def unarchive_habit(habit, actor) do
    with :ok <- authorize_owner(habit, actor) do
      habit |> Ash.Changeset.for_update(:unarchive, %{}, authorize?: false) |> Ash.update()
    end
  end

  @doc "Exclui o hábito definitivamente (não é reversível como arquivar/desarquivar) — atividades já geradas viram capturas soltas (`habit_id` some, `on_delete: :nilify`)."
  def delete_habit(habit, actor) do
    with :ok <- authorize_owner(habit, actor) do
      Ash.destroy(habit, authorize?: false, return_destroyed?: true)
    end
  end

  @doc """
  Garante a instância de hoje de um hábito devido, resolve como não cumprida
  qualquer instância vencida (dia passado, ainda pendente) do mesmo hábito, e
  preenche como não cumprido qualquer dia devido no passado que nunca chegou
  a gerar instância (usuário não abriu o app naquele dia — sem isso o dia
  simplesmente não aparecia no Histórico, em vez de aparecer como não
  cumprido). Cada dia devido gera sua própria instância independente; o que
  não foi feito ontem não trava o que é devido hoje.
  """
  def ensure_today_habit_instance(%Habit{} = habit, actor) do
    with :ok <- authorize_owner(habit, actor) do
      backfill_missing_habit_instances(habit, actor)
      close_overdue_habit_instances(habit, actor)

      today = Clock.today()

      if habit_due_on?(habit, today) and not habit_instance_exists?(habit.id, today) do
        create_activity(actor, %{
          title: occurrence_title(habit, today),
          habit_id: habit.id,
          logical_date: today
        })
      end

      :ok
    end
  end

  @doc "Aplica `ensure_today_habit_instance/2` a todo hábito ativo do usuário — chamado no mount da Tela do dia."
  def ensure_today_habit_instances(%{id: user_id} = actor) do
    Habit
    |> Ash.Query.filter(user_id == ^user_id and is_nil(archived_at))
    |> Ash.read!(authorize?: false)
    |> Enum.each(&ensure_today_habit_instance(&1, actor))
  end

  # Dia devido no passado sem nenhuma instância (`Activity`) é um dia que o
  # hábito ficou devido enquanto o usuário não abriu o app — sem instância
  # não tem o que `close_overdue_habit_instances/2` feche, então o dia some
  # do Histórico em vez de aparecer como não cumprido. Varre de `starts_on`
  # (ou da criação do hábito, se nunca mudou de regra) até ontem e cria já
  # resolvida como não cumprida cada data devida sem instância.
  defp backfill_missing_habit_instances(habit, actor) do
    lower_bound = habit.starts_on || DateTime.to_date(habit.inserted_at)
    yesterday = Date.add(Clock.today(), -1)

    if Date.compare(lower_bound, yesterday) != :gt do
      existing_dates =
        Activity
        |> Ash.Query.filter(
          habit_id == ^habit.id and logical_date >= ^lower_bound and logical_date <= ^yesterday
        )
        |> Ash.Query.select([:logical_date])
        |> Ash.read!(authorize?: false)
        |> MapSet.new(& &1.logical_date)

      lower_bound
      |> Date.range(yesterday)
      |> Enum.each(fn date ->
        if habit_due_on?(habit, date) and not MapSet.member?(existing_dates, date) do
          {:ok, activity} =
            create_activity(actor, %{
              title: occurrence_title(habit, date),
              habit_id: habit.id,
              logical_date: date
            })

          mark_activity_not_done(activity, actor)
        end
      end)
    end
  end

  defp close_overdue_habit_instances(habit, actor) do
    today = Clock.today()

    Activity
    |> Ash.Query.filter(habit_id == ^habit.id and status == :pendente and logical_date < ^today)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&mark_activity_not_done(&1, actor))
  end

  defp habit_instance_exists?(habit_id, date) do
    Activity
    |> Ash.Query.filter(habit_id == ^habit_id and logical_date == ^date)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> Enum.any?()
  end

  @doc "Sequência atual de um hábito, derivada do histórico de atividades — ver `HabitRecurrence.streak/5`."
  def habit_streak(habit_id) do
    config = Ash.get!(Habit, habit_id, authorize?: false)

    statuses_by_date =
      Activity
      |> Ash.Query.filter(habit_id == ^habit_id)
      |> Ash.Query.select([:logical_date, :status])
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.logical_date, &1.status})

    skipped_dates =
      HabitOverride
      |> Ash.Query.filter(habit_id == ^habit_id and skipped == true)
      |> Ash.Query.select([:date])
      |> Ash.read!(authorize?: false)
      |> MapSet.new(& &1.date)

    HabitRecurrence.streak(config, statuses_by_date, Clock.today(), skipped_dates)
  end

  @doc """
  Prévia dos próximos `days` dias (a partir de amanhã — hoje já tem a
  própria tela): hábitos ativos devidos e atividades adiadas (ver
  `snooze_activity/3`) que reaparecem naquele dia. Só orientação: não gera
  nenhuma `Activity` nova (isso só acontece na Tela do dia), é a mesma
  checagem que `ensure_today_habit_instance/2` faria, projetada pra frente
  — já considerando exceção por data (`HabitOverride`: "pular esse dia"
  tira o hábito daquele dia, título de exceção substitui o do hábito só
  naquele dia). Cada entrada de `day.habits` é `%{habit: %Habit{}, title:
  String.t()}` — `title` é o efetivo pra aquele dia (`occurrence_title/2`),
  não necessariamente `habit.title`. `day.snoozed` é a lista de `Activity`
  cujo `snoozed_until` cai naquele dia.
  """
  def upcoming_habit_schedule(%{id: user_id}, days \\ 7) do
    habits =
      Habit
      |> Ash.Query.filter(user_id == ^user_id and is_nil(archived_at))
      |> Ash.Query.load(item: [:category])
      |> Ash.read!(authorize?: false)

    tomorrow = Date.add(Clock.today(), 1)
    last_day = Date.add(tomorrow, days - 1)

    snoozed_by_date =
      Activity
      |> Ash.Query.filter(
        user_id == ^user_id and not is_nil(snoozed_until) and snoozed_until >= ^tomorrow and
          snoozed_until <= ^last_day
      )
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(item: [:category])
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.snoozed_until)

    Enum.map(0..(days - 1), fn offset ->
      date = Date.add(tomorrow, offset)

      due =
        habits
        |> Enum.filter(&habit_due_on?(&1, date))
        |> Enum.map(&%{habit: &1, title: occurrence_title(&1, date)})

      %{date: date, habits: due, snoozed: Map.get(snoozed_by_date, date, [])}
    end)
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

  # `item_id` e `habit_id` juntos são inválidos (ver `validate` em
  # `Activity.create`) — não crasha aqui, só deixa a criação seguir até essa
  # validação rejeitar com uma mensagem de erro decente.
  defp next_activity_position(user_id, item_id, habit_id, flow)
       when not is_nil(item_id) and not is_nil(habit_id) do
    next_activity_position(user_id, item_id, nil, flow)
  end

  defp next_activity_position(user_id, nil, nil, flow) do
    Activity
    |> Ash.Query.filter(
      user_id == ^user_id and is_nil(item_id) and is_nil(habit_id) and flow == ^flow
    )
    |> next_position_for()
  end

  defp next_activity_position(user_id, item_id, nil, flow) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and item_id == ^item_id and flow == ^flow)
    |> next_position_for()
  end

  defp next_activity_position(user_id, nil, habit_id, flow) do
    Activity
    |> Ash.Query.filter(user_id == ^user_id and habit_id == ^habit_id and flow == ^flow)
    |> next_position_for()
  end
end
