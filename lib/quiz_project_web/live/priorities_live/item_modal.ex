defmodule QuizProjectWeb.PrioritiesLive.ItemModal do
  @moduledoc """
  Editor de um item de Prioridades: progresso específico do tipo, título e
  notas, tags, categorias secundárias e campos customizados.

  Usado de duas formas, via o assign `standalone`:
    * `standalone={false}` — embutido como modal em `Index`/`Ranking`/`Browse`,
      sem sair da página onde o usuário estava.
    * `standalone={true}` — página cheia própria, usada por `PrioritiesLive.Show`
      (é o que abre quando o link é aberto numa aba nova, ver `Components.item_card/1`).

  Fechar (✕, backdrop, Escape) não tem `phx-target`: sobe pro LiveView pai de
  propósito, que é quem decide parar de renderizar este componente — o
  componente em si não sabe fechar sozinho.
  """
  use QuizProjectWeb, :live_component

  alias QuizProject.AdaptiveStudy
  alias QuizProject.Priorities
  alias QuizProject.Quizzes
  alias QuizProjectWeb.PrioritiesLive.Components

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_new_field_form?, fn -> false end)
      |> assign_new(:new_field_type, fn -> "text" end)
      |> assign_new(:type_form_value, fn -> nil end)
      |> assign_new(:active_tab, fn -> :details end)
      |> assign_new(:new_activity_title, fn -> "" end)
      |> assign_new(:new_activity_type, fn -> "tarefa" end)
      |> assign_new(:new_activity_frequency, fn -> "daily" end)
      |> assign_new(:books, fn -> AdaptiveStudy.list_books(assigns.current_user) end)
      |> assign_new(:quizzes, fn -> Quizzes.list_created(assigns.current_user) end)
      |> load_item(assigns.item_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("update_item", %{"title" => title, "notes" => notes}, socket) do
    user = socket.assigns.current_user

    case Priorities.update_item(
           socket.assigns.item,
           %{title: String.trim(title), notes: notes},
           user
         ) do
      {:ok, _} ->
        {:noreply, socket |> notify_flash(:info, "Salvo.") |> load_item(socket.assigns.item.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar.")}
    end
  end

  @impl true
  def handle_event("delete_item", _params, socket) do
    item = socket.assigns.item
    user = socket.assigns.current_user

    case Priorities.delete_item(item, user) do
      {:ok, _} ->
        send(self(), {:priorities_item_deleted, item.id})
        {:noreply, socket}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível excluir.")}
    end
  end

  @impl true
  def handle_event("toggle_archive", _params, socket) do
    item = socket.assigns.item
    user = socket.assigns.current_user

    result =
      if item.archived_at,
        do: Priorities.unarchive_item(item, user),
        else: Priorities.archive_item(item, user)

    case result do
      {:ok, _} -> {:noreply, load_item(socket, item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível atualizar.")}
    end
  end

  @impl true
  def handle_event("set_course_progress", params, socket) do
    user = socket.assigns.current_user

    attrs = %{
      course_completed_steps: parse_int(params["course_completed_steps"]) || 0,
      course_total_steps: parse_int(params["course_total_steps"])
    }

    case Priorities.set_course_progress(socket.assigns.item, attrs, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar o progresso.")}
    end
  end

  @impl true
  def handle_event("set_course_access", params, socket) do
    user = socket.assigns.current_user

    attrs = %{
      course_access_link: blank_to_nil(params["course_access_link"]),
      course_access_login: blank_to_nil(params["course_access_login"]),
      course_access_password: blank_to_nil(params["course_access_password"])
    }

    case Priorities.set_course_access(socket.assigns.item, attrs, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar o acesso.")}
    end
  end

  @impl true
  def handle_event("type_form_change", %{"item_type" => type}, socket) do
    {:noreply, assign(socket, type_form_value: type)}
  end

  @impl true
  def handle_event("change_type", params, socket) do
    user = socket.assigns.current_user

    with {:ok, attrs} <- build_change_type_attrs(params),
         {:ok, _} <- Priorities.change_item_type(socket.assigns.item, attrs, user) do
      {:noreply,
       socket
       |> notify_flash(:info, "Tipo atualizado.")
       |> assign(type_form_value: nil)
       |> load_item(socket.assigns.item.id)}
    else
      _ ->
        {:noreply,
         notify_flash(socket, :error, "Não foi possível trocar o tipo. Confira os campos.")}
    end
  end

  @impl true
  def handle_event("set_manual_percent", %{"manual_percent" => value}, socket) do
    user = socket.assigns.current_user
    percent = (parse_int(value) || 0) |> max(0) |> min(100)

    case Priorities.set_manual_percent(socket.assigns.item, percent, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar.")}
    end
  end

  @impl true
  def handle_event("set_manual_steps", params, socket) do
    user = socket.assigns.current_user

    attrs = %{
      manual_completed_steps: parse_int(params["manual_completed_steps"]) || 0,
      manual_total_steps: parse_int(params["manual_total_steps"])
    }

    case Priorities.set_manual_steps(socket.assigns.item, attrs, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar o progresso.")}
    end
  end

  @impl true
  def handle_event("switch_manual_mode", %{"mode" => "percent"}, socket) do
    item = socket.assigns.item
    user = socket.assigns.current_user
    {:percent, percent} = Priorities.progress_for_item(item)

    attrs = %{manual_progress_mode: :percent, manual_percent: percent || item.manual_percent}

    case Priorities.set_manual_mode(item, attrs, user) do
      {:ok, _} -> {:noreply, load_item(socket, item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar.")}
    end
  end

  @impl true
  def handle_event("switch_manual_mode", %{"mode" => "steps"}, socket) do
    user = socket.assigns.current_user

    case Priorities.set_manual_mode(socket.assigns.item, %{manual_progress_mode: :steps}, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar.")}
    end
  end

  @impl true
  def handle_event("set_tier", %{"tier" => value}, socket) do
    user = socket.assigns.current_user

    with {:ok, tier} <- parse_tier(value),
         {:ok, _} <- Priorities.set_tier(socket.assigns.item, tier, user) do
      {:noreply, load_item(socket, socket.assigns.item.id)}
    else
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível salvar o tier.")}
    end
  end

  @impl true
  def handle_event("create_task", %{"title" => title}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, socket}
    else
      {:ok, _} = Priorities.create_task(socket.assigns.item, title, socket.assigns.current_user)
      {:noreply, load_item(socket, socket.assigns.item.id)}
    end
  end

  @impl true
  def handle_event("toggle_task", %{"id" => id}, socket) do
    task = Enum.find(socket.assigns.tasks, &(&1.id == id))

    if task do
      {:ok, _} = Priorities.toggle_task(task, socket.assigns.item, socket.assigns.current_user)
    end

    {:noreply, load_item(socket, socket.assigns.item.id)}
  end

  @impl true
  def handle_event("add_tag", %{"name" => name}, socket) do
    name = String.trim(name)
    user = socket.assigns.current_user

    if name == "" do
      {:noreply, socket}
    else
      with {:ok, tag} <- Priorities.find_or_create_tag(user, name),
           {:ok, _} <- Priorities.add_tag_to_item(socket.assigns.item, tag, user) do
        {:noreply, load_item(socket, socket.assigns.item.id)}
      else
        _ -> {:noreply, notify_flash(socket, :error, "Não foi possível adicionar a tag.")}
      end
    end
  end

  @impl true
  def handle_event("remove_tag", %{"id" => id}, socket) do
    tag = Enum.find(socket.assigns.item.tags, &(&1.id == id))

    if tag do
      {:ok, _} =
        Priorities.remove_tag_from_item(socket.assigns.item, tag, socket.assigns.current_user)
    end

    {:noreply, load_item(socket, socket.assigns.item.id)}
  end

  @impl true
  def handle_event("add_secondary_category", %{"category_id" => id}, socket) do
    user = socket.assigns.current_user
    category = Enum.find(socket.assigns.other_categories, &(&1.id == id))

    case category && Priorities.add_secondary_category(socket.assigns.item, category, user) do
      {:ok, _} -> {:noreply, load_item(socket, socket.assigns.item.id)}
      _ -> {:noreply, notify_flash(socket, :error, "Não foi possível associar a categoria.")}
    end
  end

  @impl true
  def handle_event("remove_secondary_category", %{"id" => id}, socket) do
    category = Enum.find(socket.assigns.item.secondary_categories, &(&1.id == id))

    if category do
      {:ok, _} =
        Priorities.remove_secondary_category(
          socket.assigns.item,
          category,
          socket.assigns.current_user
        )
    end

    {:noreply, load_item(socket, socket.assigns.item.id)}
  end

  @impl true
  def handle_event("toggle_new_field_form", _params, socket) do
    {:noreply, update(socket, :show_new_field_form?, &(!&1))}
  end

  @impl true
  def handle_event("field_form_change", %{"field_type" => type}, socket) do
    {:noreply, assign(socket, new_field_type: type)}
  end

  @impl true
  def handle_event("create_field_definition", params, socket) do
    user = socket.assigns.current_user
    name = String.trim(params["name"] || "")

    with true <- name != "",
         {:ok, field_type} <- parse_field_type(params["field_type"]) do
      attrs =
        %{name: name, field_type: field_type}
        |> maybe_put_select_options(field_type, params["select_options"])

      case Priorities.create_field_definition(user, attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> notify_flash(:info, "Campo customizado criado.")
           |> assign(show_new_field_form?: false)
           |> load_item(socket.assigns.item.id)}

        _ ->
          {:noreply, notify_flash(socket, :error, "Não foi possível criar o campo.")}
      end
    else
      _ -> {:noreply, notify_flash(socket, :error, "Dê um nome para o campo.")}
    end
  end

  @impl true
  def handle_event(
        "set_field_value",
        %{"field_definition_id" => def_id, "value" => value},
        socket
      ) do
    user = socket.assigns.current_user
    definition = Enum.find(socket.assigns.field_definitions, &(&1.id == def_id))

    case definition && Priorities.set_field_value(socket.assigns.item, definition, value, user) do
      {:ok, _} ->
        {:noreply,
         socket |> notify_flash(:info, "Campo salvo.") |> load_item(socket.assigns.item.id)}

      _ ->
        {:noreply, notify_flash(socket, :error, "Não foi possível salvar o campo.")}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: parse_tab(tab))}
  end

  @impl true
  def handle_event("new_activity_form_change", params, socket) do
    {:noreply,
     assign(socket,
       new_activity_title: Map.get(params, "title", ""),
       new_activity_type: Map.get(params, "type", "tarefa"),
       new_activity_frequency: Map.get(params, "frequency", "daily")
     )}
  end

  @impl true
  def handle_event("create_item_activity", params, socket) do
    title = params |> Map.get("title", "") |> String.trim()
    user = socket.assigns.current_user
    item = socket.assigns.item
    is_habit? = Map.get(params, "type") == "habito"
    is_event? = Map.get(params, "type") == "evento"

    cond do
      title == "" ->
        {:noreply, socket}

      is_habit? ->
        attrs = Map.merge(%{title: title, item_id: item.id}, build_habit_attrs(params))

        case Priorities.create_habit(user, attrs) do
          {:ok, habit} ->
            Priorities.ensure_today_habit_instance(habit, user)

            {:noreply,
             socket
             |> notify_flash(:info, "Hábito criado — acompanhe na Tela do Dia, não aqui.")
             |> assign(
               new_activity_title: "",
               new_activity_type: "tarefa",
               new_activity_frequency: "daily"
             )
             |> load_item(item.id)}

          _ ->
            {:noreply, notify_flash(socket, :error, "Não foi possível criar o hábito.")}
        end

      true ->
        attrs = Map.merge(%{title: title, item_id: item.id}, event_attrs(is_event?, params))

        case Priorities.create_activity(user, attrs) do
          {:ok, _} ->
            flash = if is_event?, do: "Evento criado.", else: "Atividade criada."

            {:noreply,
             socket
             |> notify_flash(:info, flash)
             |> assign(new_activity_title: "", new_activity_type: "tarefa")
             |> load_item(item.id)}

          _ ->
            {:noreply, notify_flash(socket, :error, "Não foi possível criar a atividade.")}
        end
    end
  end

  @impl true
  def handle_event("complete_item_activity", %{"id" => id}, socket),
    do: {:noreply, resolve_activity(socket, id, &Priorities.complete_activity/2)}

  @impl true
  def handle_event("mark_item_activity_not_done", %{"id" => id}, socket),
    do: {:noreply, resolve_activity(socket, id, &Priorities.mark_activity_not_done/2)}

  @impl true
  def handle_event("discard_item_activity", %{"id" => id}, socket),
    do: {:noreply, resolve_activity(socket, id, &Priorities.discard_activity/2)}

  @impl true
  def handle_event("reopen_item_activity", %{"id" => id}, socket),
    do: {:noreply, resolve_activity(socket, id, &Priorities.reopen_activity/2)}

  @impl true
  def handle_event("cancel_item_activity_snooze", %{"id" => id}, socket),
    do: {:noreply, resolve_activity(socket, id, &Priorities.clear_activity_snooze/2)}

  defp resolve_activity(socket, id, fun) do
    activity = Enum.find(socket.assigns.activities, &(&1.id == id))

    if activity do
      {:ok, _} = fun.(activity, socket.assigns.current_user)
    end

    load_item(socket, socket.assigns.item.id)
  end

  defp parse_tab("activities"), do: :activities
  defp parse_tab("historico"), do: :historico
  defp parse_tab(_), do: :details

  # `put_flash/3` num LiveComponent só grava no `assigns.flash` isolado do
  # componente, que nunca é renderizado — quem mostra `@flash` é o
  # `Layouts.app` do LiveView pai. Por isso o flash sai daqui como mensagem
  # (`self()` aponta pro processo do LiveView, dono do componente) e cada
  # LiveView que hospeda este componente trata `{:priorities_flash, ...}`
  # chamando `put_flash/3` de verdade no seu próprio socket.
  defp notify_flash(socket, kind, message) do
    send(self(), {:priorities_flash, kind, message})
    socket
  end

  @tiers ~w(S A B C D)

  defp parse_tier(""), do: {:ok, nil}
  defp parse_tier(value) when value in @tiers, do: {:ok, String.to_existing_atom(value)}
  defp parse_tier(_value), do: :error

  defp load_item(socket, id) do
    user = socket.assigns.current_user
    {:ok, item} = Priorities.get_item(id, user)

    assign(socket,
      item: item,
      progress: Priorities.progress_for_item(item),
      tasks: if(item.item_type == :checklist, do: Priorities.list_tasks(item.id), else: []),
      other_categories:
        Enum.reject(Priorities.list_categories(user), &(&1.id == item.category_id)),
      field_definitions: Priorities.list_field_definitions(user),
      activities: Priorities.list_activities_for_item(item.id, user),
      item_logs: Priorities.list_item_logs(item.id)
    )
  end

  # `Clock`/`inserted_at` gravam em UTC — mesmo deslocamento fixo de
  # Brasília (ver `QuizProject.Priorities.Clock`) só pra exibir a hora.
  # Mostra a data também: o histórico cruza vários dias.
  defp local_datetime(datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%d/%m %H:%M:%S")
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp build_habit_attrs(%{"frequency" => "weekly"} = params) do
    %{frequency: :weekly, weekdays: parse_int_list(params["weekdays"]), month_days: []}
  end

  defp build_habit_attrs(%{"frequency" => "monthly"} = params) do
    %{frequency: :monthly, weekdays: [], month_days: parse_int_list(params["month_days"])}
  end

  defp build_habit_attrs(_params) do
    %{frequency: :daily, weekdays: [], month_days: []}
  end

  defp parse_int_list(nil), do: []
  defp parse_int_list(values) when is_list(values), do: Enum.map(values, &String.to_integer/1)

  # `logical_date` inválida ou em branco cai no default de hoje que
  # `Priorities.create_activity/2` já aplica — só força a data quando o
  # usuário de fato escolheu uma.
  defp event_attrs(false, _params), do: %{}

  defp event_attrs(true, params) do
    case params |> Map.get("event_date", "") |> Date.from_iso8601() do
      {:ok, date} -> %{kind: :evento, logical_date: date}
      _ -> %{kind: :evento}
    end
  end

  @item_types ~w(book quiz_goal course checklist manual)

  defp parse_item_type(value) when value in @item_types,
    do: {:ok, String.to_existing_atom(value)}

  defp parse_item_type(_value), do: :error

  defp build_change_type_attrs(params) do
    with {:ok, item_type} <- parse_item_type(params["item_type"]) do
      base = %{item_type: item_type}

      attrs =
        case item_type do
          :book -> Map.put(base, :study_material_id, blank_to_nil(params["study_material_id"]))
          :quiz_goal -> Map.put(base, :quiz_id, blank_to_nil(params["quiz_id"]))
          :course -> Map.put(base, :course_total_steps, parse_int(params["course_total_steps"]))
          _ -> base
        end

      {:ok, attrs}
    end
  end

  @field_types ~w(text select number)

  defp parse_field_type(value) when value in @field_types,
    do: {:ok, String.to_existing_atom(value)}

  defp parse_field_type(_value), do: :error

  defp maybe_put_select_options(attrs, :select, raw) do
    options =
      (raw || "") |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    Map.put(attrs, :select_options, options)
  end

  defp maybe_put_select_options(attrs, _type, _raw), do: attrs

  defp field_value_for(item, definition) do
    Enum.find(item.field_values, &(&1.field_definition_id == definition.id))
  end

  defp field_current_value(nil, _definition), do: ""
  defp field_current_value(%{value_number: n}, %{field_type: :number}), do: n && to_string(n)
  defp field_current_value(%{value_text: t}, _definition), do: t || ""

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div :if={@standalone} class="mx-auto max-w-3xl space-y-6">
        <.item_header item={@item} myself={@myself} />
        <.item_tabs
          myself={@myself}
          active_tab={@active_tab}
          activities={@activities}
          item_logs={@item_logs}
        />
        <.content_body
          myself={@myself}
          item={@item}
          progress={@progress}
          tasks={@tasks}
          other_categories={@other_categories}
          field_definitions={@field_definitions}
          show_new_field_form?={@show_new_field_form?}
          new_field_type={@new_field_type}
          type_form_value={@type_form_value}
          books={@books}
          quizzes={@quizzes}
          active_tab={@active_tab}
          activities={@activities}
          new_activity_title={@new_activity_title}
          new_activity_type={@new_activity_type}
          new_activity_frequency={@new_activity_frequency}
          item_logs={@item_logs}
        />
      </div>

      <div
        :if={!@standalone}
        class="modal modal-open"
        phx-window-keydown="close_item_modal"
        phx-key="Escape"
      >
        <div class="modal-box flex max-h-[85vh] max-w-2xl flex-col overflow-hidden rounded-3xl p-0">
          <div class="shrink-0 space-y-3 border-b border-base-300 px-6 pb-4 pt-6">
            <.item_header item={@item} myself={@myself}>
              <:extra_actions>
                <button
                  type="button"
                  phx-click="close_item_modal"
                  class="btn btn-sm btn-circle btn-ghost"
                  aria-label="Fechar"
                >
                  ✕
                </button>
              </:extra_actions>
            </.item_header>
            <.item_tabs
              myself={@myself}
              active_tab={@active_tab}
              activities={@activities}
              item_logs={@item_logs}
            />
          </div>

          <div class="flex-1 space-y-6 overflow-y-auto p-6">
            <.content_body
              myself={@myself}
              item={@item}
              progress={@progress}
              tasks={@tasks}
              other_categories={@other_categories}
              field_definitions={@field_definitions}
              show_new_field_form?={@show_new_field_form?}
              new_field_type={@new_field_type}
              type_form_value={@type_form_value}
              books={@books}
              quizzes={@quizzes}
              active_tab={@active_tab}
              activities={@activities}
              new_activity_title={@new_activity_title}
              new_activity_type={@new_activity_type}
              new_activity_frequency={@new_activity_frequency}
              item_logs={@item_logs}
            />
          </div>
        </div>

        <button
          type="button"
          phx-click="close_item_modal"
          class="modal-backdrop"
          aria-label="Fechar"
        >
          Fechar
        </button>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :myself, :any, required: true
  slot :extra_actions

  defp item_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-xl font-bold tracking-tight">{@item.title}</h1>
        <p class="text-sm opacity-70">
          {Components.item_type_label(@item.item_type)} · {@item.category.name}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          id="toggle-archive-btn"
          phx-click="toggle_archive"
          phx-target={@myself}
          class="btn btn-soft btn-sm rounded-full"
          data-confirm={
            if @item.archived_at,
              do: nil,
              else: "Arquivar este item? O progresso fica guardado, mas ele some da lista principal."
          }
        >
          <.icon name="hero-archive-box" class="size-3.5" />
          {if @item.archived_at, do: "Reativar", else: "Arquivar"}
        </button>
        <button
          id="delete-item-btn"
          phx-click="delete_item"
          phx-target={@myself}
          class="btn btn-soft btn-sm rounded-full text-error"
          data-confirm="Excluir este item definitivamente? Essa ação não pode ser desfeita."
        >
          Excluir
        </button>
        {render_slot(@extra_actions)}
      </div>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :active_tab, :atom, required: true
  attr :activities, :list, required: true
  attr :item_logs, :list, required: true

  defp item_tabs(assigns) do
    ~H"""
    <nav class="flex gap-2 text-sm font-semibold">
      <button
        type="button"
        phx-click="switch_tab"
        phx-value-tab="details"
        phx-target={@myself}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          if(@active_tab == :details,
            do: "bg-primary text-primary-content shadow-sm",
            else: "bg-base-200 opacity-70 hover:opacity-100"
          )
        ]}
      >
        Detalhes
      </button>
      <button
        type="button"
        phx-click="switch_tab"
        phx-value-tab="activities"
        phx-target={@myself}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          if(@active_tab == :activities,
            do: "bg-primary text-primary-content shadow-sm",
            else: "bg-base-200 opacity-70 hover:opacity-100"
          )
        ]}
      >
        Atividades
        <span :if={@activities != []} class="ml-0.5 opacity-70">({length(@activities)})</span>
      </button>
      <button
        type="button"
        phx-click="switch_tab"
        phx-value-tab="historico"
        phx-target={@myself}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          if(@active_tab == :historico,
            do: "bg-primary text-primary-content shadow-sm",
            else: "bg-base-200 opacity-70 hover:opacity-100"
          )
        ]}
      >
        Histórico
      </button>
    </nav>
    """
  end

  attr :myself, :any, required: true
  attr :item, :map, required: true
  attr :progress, :any, required: true
  attr :tasks, :list, required: true
  attr :other_categories, :list, required: true
  attr :field_definitions, :list, required: true
  attr :show_new_field_form?, :boolean, required: true
  attr :new_field_type, :string, required: true
  attr :type_form_value, :string, default: nil
  attr :books, :list, required: true
  attr :quizzes, :list, required: true
  attr :active_tab, :atom, required: true
  attr :activities, :list, required: true
  attr :new_activity_title, :string, required: true
  attr :new_activity_type, :string, required: true
  attr :new_activity_frequency, :string, required: true
  attr :item_logs, :list, required: true

  defp content_body(assigns) do
    ~H"""
    <div :if={@active_tab == :details} class="space-y-6">
      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Progresso</h2>
        <.type_editor
          item={@item}
          progress={@progress}
          tasks={@tasks}
          myself={@myself}
          activities={@activities}
        />
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Detalhes</h2>
        <form id="update-item-form" phx-submit="update_item" phx-target={@myself} class="space-y-3">
          <.input type="text" name="title" label="Título" value={@item.title} required />
          <.input type="textarea" name="notes" label="Notas" value={@item.notes} rows="3" />
          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">Salvar</button>
          </div>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Tipo</h2>
        <form
          id="change-type-form"
          phx-submit="change_type"
          phx-change="type_form_change"
          phx-target={@myself}
          class="space-y-3"
        >
          <.input
            type="select"
            name="item_type"
            label="Tipo"
            value={@type_form_value || Atom.to_string(@item.item_type)}
            options={Components.item_type_options()}
          />

          <.input
            :if={(@type_form_value || Atom.to_string(@item.item_type)) == "book"}
            type="select"
            name="study_material_id"
            label="Livro"
            value=""
            options={Enum.map(@books, &{&1.title, &1.id})}
            prompt="Escolha um livro"
          />

          <.input
            :if={(@type_form_value || Atom.to_string(@item.item_type)) == "quiz_goal"}
            type="select"
            name="quiz_id"
            label="Quiz"
            value=""
            options={Enum.map(@quizzes, &{quiz_display_name(&1), &1.id})}
            prompt="Escolha um quiz"
          />

          <.input
            :if={(@type_form_value || Atom.to_string(@item.item_type)) == "course"}
            type="number"
            name="course_total_steps"
            label="Total de etapas (opcional)"
            min="1"
            value=""
          />

          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">
              Salvar tipo
            </button>
          </div>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Tier</h2>
        <p class="text-xs opacity-60">
          Usado no bloco de prioridades misturadas — vários itens podem dividir o mesmo tier.
        </p>
        <form id="tier-form" phx-change="set_tier" phx-target={@myself} class="flex flex-wrap gap-4">
          <label class="flex items-center gap-1.5 text-sm">
            <input
              type="radio"
              name="tier"
              value=""
              class="radio radio-sm"
              checked={is_nil(@item.tier)}
            /> Sem tier
          </label>
          <label :for={t <- ~w(S A B C D)} class="flex items-center gap-1.5 text-sm font-semibold">
            <input
              type="radio"
              name="tier"
              value={t}
              class="radio radio-sm"
              checked={to_string(@item.tier) == t}
            /> {t}
          </label>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Tags</h2>
        <div class="flex flex-wrap items-center gap-2">
          <span :for={tag <- @item.tags} class="flex items-center gap-1">
            <Components.tag_chip tag={tag} />
            <button
              id={"remove-tag-#{tag.id}"}
              phx-click="remove_tag"
              phx-value-id={tag.id}
              phx-target={@myself}
              class="opacity-50 hover:opacity-100"
              title="Remover tag"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </span>
        </div>
        <form id="add-tag-form" phx-submit="add_tag" phx-target={@myself} class="flex items-end gap-2">
          <div class="flex-1">
            <.input type="text" name="name" label="Nova tag" value="" placeholder="Ex: urgente" />
          </div>
          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1 invisible">Adicionar</span>
              <button type="submit" class="btn btn-soft btn-sm rounded-full px-4">Adicionar</button>
            </label>
          </div>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Categorias secundárias</h2>
        <div class="flex flex-wrap items-center gap-2">
          <span
            :for={category <- @item.secondary_categories}
            class="flex items-center gap-1 rounded-full bg-base-200 px-2.5 py-0.5 text-[0.68rem] font-semibold opacity-70"
          >
            {category.name}
            <button
              id={"remove-secondary-category-#{category.id}"}
              phx-click="remove_secondary_category"
              phx-value-id={category.id}
              phx-target={@myself}
              class="opacity-50 hover:opacity-100"
              title="Remover categoria secundária"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </span>
          <p :if={@item.secondary_categories == []} class="text-xs opacity-60">Nenhuma ainda.</p>
        </div>
        <form
          :if={@other_categories != []}
          id="add-secondary-category-form"
          phx-submit="add_secondary_category"
          phx-target={@myself}
          class="flex items-end gap-2"
        >
          <div class="flex-1">
            <.input
              type="select"
              name="category_id"
              label="Adicionar categoria"
              value=""
              options={Enum.map(@other_categories, &{&1.name, &1.id})}
              prompt="Escolha uma categoria"
            />
          </div>
          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1 invisible">Adicionar</span>
              <button type="submit" class="btn btn-soft btn-sm rounded-full px-4">Adicionar</button>
            </label>
          </div>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Campos customizados</h2>
          <button
            id="toggle-new-field-form-btn"
            phx-click="toggle_new_field_form"
            phx-target={@myself}
            class="btn btn-ghost btn-xs rounded-full"
          >
            <.icon name="hero-plus" class="size-3" /> Novo campo
          </button>
        </div>

        <form
          :if={@show_new_field_form?}
          id="new-field-form"
          phx-submit="create_field_definition"
          phx-change="field_form_change"
          phx-target={@myself}
          class="space-y-3 rounded-2xl border border-base-300 p-3"
        >
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <.input type="text" name="name" label="Nome do campo" value="" required />
            <.input
              type="select"
              name="field_type"
              label="Tipo"
              value={@new_field_type}
              options={[{"Texto", "text"}, {"Seleção", "select"}, {"Número", "number"}]}
            />
          </div>
          <.input
            :if={@new_field_type == "select"}
            type="text"
            name="select_options"
            label="Opções (separadas por vírgula)"
            value=""
            placeholder="Ex: baixa, média, alta"
          />
          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">Criar campo</button>
          </div>
        </form>

        <p :if={@field_definitions == []} class="text-xs opacity-60">
          Nenhum campo customizado criado ainda.
        </p>

        <form
          :for={definition <- @field_definitions}
          id={"set-field-value-#{definition.id}"}
          phx-submit="set_field_value"
          phx-target={@myself}
          class="flex items-end gap-2"
        >
          <input type="hidden" name="field_definition_id" value={definition.id} />
          <div class="flex-1">
            <.field_value_input
              definition={definition}
              current={field_current_value(field_value_for(@item, definition), definition)}
            />
          </div>
          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1 invisible">Salvar</span>
              <button type="submit" class="btn btn-soft btn-sm rounded-full px-4">Salvar</button>
            </label>
          </div>
        </form>
      </section>
    </div>

    <div :if={@active_tab == :activities} class="space-y-4">
      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Nova atividade</h2>
        <p class="text-xs opacity-60">
          Marcar como hábito cria um hábito à parte (categoria de {@item.title}, não este item) —
          acompanhe a sequência dele na Tela do Dia, não aqui.
        </p>
        <form
          id="create-item-activity-form"
          phx-submit="create_item_activity"
          phx-change="new_activity_form_change"
          phx-target={@myself}
          class="space-y-3"
        >
          <div class="flex flex-wrap items-end gap-3">
            <div class="min-w-40 flex-1">
              <.input
                type="text"
                name="title"
                label="Título"
                value={@new_activity_title}
                placeholder="Ex: Ler capítulo 3"
              />
            </div>
            <div class="w-36">
              <.input
                type="select"
                name="type"
                label="Tipo"
                value={@new_activity_type}
                options={[{"Atividade", "tarefa"}, {"Hábito", "habito"}, {"Evento", "evento"}]}
              />
            </div>
            <div class="fieldset mb-2">
              <label>
                <span class="label mb-1 invisible">Adicionar</span>
                <button
                  type="submit"
                  class="btn btn-primary btn-sm rounded-full px-4"
                  phx-disable-with="Adicionando..."
                >
                  {cond do
                    @new_activity_type == "habito" -> "Criar hábito"
                    @new_activity_type == "evento" -> "Criar evento"
                    true -> "Adicionar"
                  end}
                </button>
              </label>
            </div>
          </div>

          <div :if={@new_activity_type == "evento"} class="rounded-2xl border border-base-300 p-3">
            <.input
              type="date"
              name="event_date"
              label="Data do evento"
              value={Date.to_iso8601(Date.utc_today())}
            />
            <p class="mt-1 text-xs opacity-60">
              Vira evento sincronizado com o Google Agenda, se conectado (ver Configurações).
            </p>
          </div>

          <div
            :if={@new_activity_type == "habito"}
            class="space-y-3 rounded-2xl border border-base-300 p-3"
          >
            <.input
              type="select"
              name="frequency"
              label="Frequência"
              value={@new_activity_frequency}
              options={[
                {"Diário", "daily"},
                {"Dias da semana", "weekly"},
                {"Dias do mês", "monthly"}
              ]}
            />

            <div :if={@new_activity_frequency == "weekly"} class="fieldset mb-2">
              <span class="label mb-1">Quais dias</span>
              <Components.day_toggle_group
                name="weekdays[]"
                selected={[]}
                options={[
                  {"Segunda", "1"},
                  {"Terça", "2"},
                  {"Quarta", "3"},
                  {"Quinta", "4"},
                  {"Sexta", "5"},
                  {"Sábado", "6"},
                  {"Domingo", "7"}
                ]}
              />
            </div>

            <div :if={@new_activity_frequency == "monthly"} class="fieldset mb-2">
              <span class="label mb-1">Quais dias do mês</span>
              <Components.day_toggle_group
                name="month_days[]"
                selected={[]}
                options={Enum.map(1..31, &{to_string(&1), to_string(&1)})}
                class="grid grid-cols-6 gap-1.5 sm:grid-cols-7"
              />
            </div>
          </div>
        </form>
      </section>

      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Todas</h2>
        <p :if={@activities == []} class="text-xs opacity-60">Nenhuma atividade ainda.</p>
        <ul :if={@activities != []} class="space-y-2">
          <li
            :for={activity <- @activities}
            class="flex items-center justify-between gap-2 rounded-2xl border border-base-200 p-2.5"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold">{activity.title}</p>
              <p class="text-xs opacity-60">
                {activity_status_label(activity.status)} · {Calendar.strftime(
                  activity.logical_date,
                  "%d/%m/%Y"
                )}
              </p>
              <p :if={activity.snoozed_until} class="text-xs font-semibold text-info">
                Adiada até {Calendar.strftime(activity.snoozed_until, "%d/%m/%Y")}
              </p>
            </div>
            <div :if={activity.status == :pendente} class="flex shrink-0 items-center gap-1">
              <button
                phx-click="complete_item_activity"
                phx-value-id={activity.id}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                title="Concluir"
              >
                <.icon name="hero-check" class="size-4 text-success" />
              </button>
              <button
                phx-click="mark_item_activity_not_done"
                phx-value-id={activity.id}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                title="Não cumprida"
              >
                <.icon name="hero-x-mark" class="size-4 text-warning" />
              </button>
              <button
                :if={activity.snoozed_until}
                phx-click="cancel_item_activity_snooze"
                phx-value-id={activity.id}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                title="Cancelar adiamento — volta a aparecer hoje"
              >
                <.icon name="hero-clock" class="size-4 text-info" />
              </button>
              <button
                phx-click="discard_item_activity"
                phx-value-id={activity.id}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                title="Descartar"
              >
                <.icon name="hero-trash" class="size-4 opacity-50" />
              </button>
            </div>
            <div :if={activity.status != :pendente} class="flex shrink-0 items-center gap-1">
              <button
                phx-click="reopen_item_activity"
                phx-value-id={activity.id}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                title="Reabrir — volta pra pendente"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4 opacity-50" />
              </button>
            </div>
          </li>
        </ul>
      </section>
    </div>

    <div :if={@active_tab == :historico} id="item-logs" class="space-y-4">
      <section class="card qcard space-y-3 border border-base-300 bg-base-100 p-5">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Histórico</h2>

        <p :if={@item_logs == []} class="text-xs opacity-60">
          Nenhum evento registrado ainda.
        </p>

        <ul :if={@item_logs != []} class="space-y-1.5">
          <li :for={log <- @item_logs} class="flex items-baseline gap-2 text-sm">
            <span class="shrink-0 opacity-40">•</span>
            <span class="shrink-0 font-mono text-xs opacity-50">
              {local_datetime(log.inserted_at)}
            </span>
            <span class="opacity-90">{log.message}</span>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp activity_status_label(:pendente), do: "Pendente"
  defp activity_status_label(:concluida), do: "Concluída"
  defp activity_status_label(:nao_cumprida), do: "Não cumprida"
  defp activity_status_label(:descartada), do: "Descartada"

  attr :item, :map, required: true
  attr :progress, :any, required: true
  attr :tasks, :list, required: true
  attr :myself, :any, required: true
  attr :activities, :list, default: []

  defp type_editor(%{item: %{item_type: :book}} = assigns) do
    ~H"""
    <p class="text-sm">
      <span :if={@item.study_material}>
        <.link
          navigate={~p"/contents/#{@item.study_material_id}"}
          class="font-semibold text-primary hover:underline"
        >
          {@item.study_material.title}
        </.link>
        <span :if={@item.study_material.author} class="opacity-60">
          · {@item.study_material.author}
        </span>
      </span>
      <span :if={!@item.study_material} class="opacity-60">
        Este livro não está mais na sua biblioteca.
      </span>
    </p>
    <.percent_bar progress={@progress} />
    """
  end

  defp type_editor(%{item: %{item_type: :quiz_goal}} = assigns) do
    ~H"""
    <p :if={@item.quiz} class="text-sm">
      <.link
        navigate={~p"/quiz/#{@item.quiz_id}/evolution"}
        class="font-semibold text-primary hover:underline"
      >
        {quiz_display_name(@item.quiz)}
      </.link>
      <span class="opacity-60"> — melhor resultado entre as tentativas</span>
    </p>
    <p :if={!@item.quiz} class="text-sm opacity-60">Este quiz não existe mais.</p>
    <.percent_bar progress={@progress} />
    """
  end

  defp type_editor(%{item: %{item_type: :course}} = assigns) do
    ~H"""
    <.percent_bar progress={@progress} />
    <form
      id="course-progress-form"
      phx-submit="set_course_progress"
      phx-target={@myself}
      class="flex flex-wrap items-end gap-3"
    >
      <div class="w-32">
        <.input
          type="number"
          name="course_completed_steps"
          label="Concluídas"
          value={@item.course_completed_steps}
          min="0"
        />
      </div>
      <div class="w-32">
        <.input
          type="number"
          name="course_total_steps"
          label="Total"
          value={@item.course_total_steps}
          min="1"
        />
      </div>
      <div class="fieldset mb-2">
        <label>
          <span class="label mb-1 invisible">Salvar</span>
          <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">Salvar</button>
        </label>
      </div>
    </form>

    <form
      id="course-access-form"
      phx-submit="set_course_access"
      phx-target={@myself}
      class="space-y-3 border-t border-base-200 pt-3"
    >
      <p class="text-xs font-semibold uppercase tracking-wide opacity-50">Método de acesso</p>
      <.input
        type="text"
        name="course_access_link"
        label="Link"
        value={@item.course_access_link}
      />
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <.input
          type="text"
          name="course_access_login"
          label="Login"
          value={@item.course_access_login}
        />
        <.input
          type="text"
          name="course_access_password"
          label="Senha"
          value={@item.course_access_password}
        />
      </div>
      <div class="flex justify-end">
        <button type="submit" class="btn btn-soft btn-sm rounded-full px-5">Salvar acesso</button>
      </div>
    </form>
    """
  end

  defp type_editor(%{item: %{item_type: :checklist}} = assigns) do
    ~H"""
    <.percent_bar progress={@progress} />
    <ul class="space-y-1">
      <li :for={task <- @tasks} class="flex items-center gap-2">
        <button
          id={"toggle-task-#{task.id}"}
          phx-click="toggle_task"
          phx-value-id={task.id}
          phx-target={@myself}
          class="flex items-center gap-2 text-left text-sm"
        >
          <.icon :if={task.done} name="hero-check-circle-solid" class="size-4 text-primary" />
          <span
            :if={!task.done}
            class="size-4 shrink-0 rounded-full border-2 border-base-content/40"
          />
          <span class={task.done && "opacity-50 line-through"}>{task.title}</span>
        </button>
      </li>
    </ul>
    <form
      id="create-task-form"
      phx-submit="create_task"
      phx-target={@myself}
      class="flex items-end gap-2"
    >
      <div class="flex-1">
        <.input
          type="text"
          name="title"
          label="Nova subtarefa"
          value=""
          placeholder="Ex: Ler capítulo 3"
        />
      </div>
      <div class="fieldset mb-2">
        <label>
          <span class="label mb-1 invisible">Adicionar</span>
          <button type="submit" class="btn btn-soft btn-sm rounded-full px-4">Adicionar</button>
        </label>
      </div>
    </form>
    """
  end

  defp type_editor(%{item: %{item_type: :manual}} = assigns) do
    ~H"""
    <.percent_bar progress={@progress} />
    <div class="join">
      <button
        type="button"
        phx-click="switch_manual_mode"
        phx-value-mode="percent"
        phx-target={@myself}
        class={["btn btn-sm join-item", @item.manual_progress_mode == :percent && "btn-primary"]}
      >
        Percentual
      </button>
      <button
        type="button"
        phx-click="switch_manual_mode"
        phx-value-mode="steps"
        phx-target={@myself}
        class={["btn btn-sm join-item", @item.manual_progress_mode == :steps && "btn-primary"]}
      >
        Etapas
      </button>
    </div>
    <form
      :if={@item.manual_progress_mode == :percent}
      id="manual-percent-form"
      phx-submit="set_manual_percent"
      phx-target={@myself}
      class="flex items-end gap-3"
    >
      <div class="w-32">
        <.input
          type="number"
          name="manual_percent"
          label="Percentual"
          value={@item.manual_percent}
          min="0"
          max="100"
        />
      </div>
      <div class="fieldset mb-2">
        <label>
          <span class="label mb-1 invisible">Salvar</span>
          <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">Salvar</button>
        </label>
      </div>
    </form>
    <form
      :if={@item.manual_progress_mode == :steps}
      id="manual-steps-form"
      phx-submit="set_manual_steps"
      phx-target={@myself}
      class="flex flex-wrap items-end gap-3"
    >
      <div class="w-32">
        <.input
          type="number"
          name="manual_completed_steps"
          label="Concluídas"
          value={@item.manual_completed_steps}
          min="0"
        />
      </div>
      <div class="w-32">
        <.input
          type="number"
          name="manual_total_steps"
          label="Total"
          value={@item.manual_total_steps}
          min="1"
        />
      </div>
      <div class="fieldset mb-2">
        <label>
          <span class="label mb-1 invisible">Salvar</span>
          <button type="submit" class="btn btn-primary btn-sm rounded-full px-5">Salvar</button>
        </label>
      </div>
    </form>
    """
  end

  attr :progress, :any, required: true

  defp percent_bar(%{progress: {:percent, percent}} = assigns) do
    assigns = assign(assigns, :percent, percent)

    ~H"""
    <div class="space-y-1">
      <Components.progress_bar percent={@percent} />
      <p class="text-xs opacity-70">{@percent || 0}%</p>
    </div>
    """
  end

  defp percent_bar(assigns), do: ~H""

  attr :definition, :map, required: true
  attr :current, :any, required: true

  defp field_value_input(%{definition: %{field_type: :select}} = assigns) do
    ~H"""
    <.input
      type="select"
      name="value"
      label={@definition.name}
      value={@current}
      options={@definition.select_options}
      prompt="Escolha um valor"
    />
    """
  end

  defp field_value_input(%{definition: %{field_type: :number}} = assigns) do
    ~H"""
    <.input type="number" name="value" label={@definition.name} value={@current} step="any" />
    """
  end

  defp field_value_input(assigns) do
    ~H"""
    <.input type="text" name="value" label={@definition.name} value={@current} />
    """
  end

  defp quiz_display_name(%{versions: [latest | _]}), do: latest.name || "Quiz sem nome"
  defp quiz_display_name(_quiz), do: "Quiz sem nome"
end
