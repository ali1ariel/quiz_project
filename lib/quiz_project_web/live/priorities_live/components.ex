defmodule QuizProjectWeb.PrioritiesLive.Components do
  @moduledoc """
  Pedaços de UI compartilhados entre as telas de Prioridades (Index, Show,
  Ranking, Browse) — cada uma mostra itens vindos de consultas diferentes,
  mas o cartão e a barra de progresso são sempre os mesmos.
  """
  use QuizProjectWeb, :html

  alias QuizProject.Priorities

  # Paleta fixa — a cor de uma categoria vem de um hash do seu `id` (não da
  # posição), então reordenar categorias nunca muda a cor de ninguém.
  #
  # O token (ex: "red-400") é usado via `style` inline pra montar
  # `var(--color-red-400)`, e não como classe `border-l-red-400`: o `.qcard`
  # deste projeto (assets/css/app.css) define `border` com a propriedade
  # shorthand em CSS puro, na mesma camada `@layer utilities` do Tailwind mas
  # depois das classes geradas no arquivo compilado — então uma classe
  # `border-l-*` perde a cascata pra ela. Inline `style` sempre vence
  # qualquer regra de folha de estilo, então é o jeito robusto de pintar a
  # borda sem depender da ordem de geração do CSS. A classe `bg-*` (usada só
  # no indicador redondo, sem conflito de `border` nenhum) continua uma
  # classe Tailwind normal, escrita por extenso aqui — não montada por
  # interpolação — porque o Tailwind escaneia o texto do arquivo em busca de
  # classes literais.
  @category_colors [
    {"red-400", "bg-red-400"},
    {"orange-400", "bg-orange-400"},
    {"amber-400", "bg-amber-400"},
    {"lime-400", "bg-lime-400"},
    {"emerald-400", "bg-emerald-400"},
    {"teal-400", "bg-teal-400"},
    {"cyan-400", "bg-cyan-400"},
    {"blue-400", "bg-blue-400"},
    {"indigo-400", "bg-indigo-400"},
    {"violet-400", "bg-violet-400"},
    {"fuchsia-400", "bg-fuchsia-400"},
    {"pink-400", "bg-pink-400"}
  ]

  @doc "Cor estável da categoria: `{token_da_variável_css, classe_de_fundo}`, sempre a mesma para o mesmo id."
  def category_colors(category_id) do
    index = :erlang.phash2(category_id, length(@category_colors))
    Enum.at(@category_colors, index)
  end

  @doc """
  Opções do segundo `<select>` do dropdown "Anexar" (cascata categoria →
  prioridade): as prioridades de uma categoria, com o item "Geral" dela
  rotulado com o próprio nome da categoria (não seu título real, tipo
  "Corpo - Geral") — pra aparecer na lista como "a categoria em si".
  """
  def attach_item_options(items, category) do
    Enum.map(items, fn item ->
      label = if item.general, do: category.name, else: item.title
      {label, item.id}
    end)
  end

  attr :percent, :integer, default: nil

  def progress_bar(assigns) do
    ~H"""
    <div class="h-1 overflow-hidden rounded-full bg-base-200">
      <div class="h-full bg-primary transition-all" style={"width: #{@percent || 0}%"}></div>
    </div>
    """
  end

  attr :tag, :map, required: true

  def tag_chip(assigns) do
    ~H"""
    <span class="rounded-full bg-base-200 px-2.5 py-0.5 text-[0.68rem] font-semibold opacity-70">
      {@tag.name}
    </span>
    """
  end

  attr :item, :map, required: true
  attr :show_category, :boolean, default: false

  def item_card(assigns) do
    {color_token, _bg_color} = category_colors(assigns.item.category_id)

    assigns =
      assigns
      |> assign(:progress, Priorities.progress_for_item(assigns.item))
      |> assign(:border_style, "border-left: 4px solid var(--color-#{color_token});")

    ~H"""
    <div
      id={"item-card-#{@item.id}"}
      style={@border_style}
      class="card qcard flex flex-col gap-2 border border-base-300 bg-base-100 p-4 transition hover:shadow-md"
    >
      <div class="flex items-start justify-between gap-2">
        <h3 class="line-clamp-2 text-sm font-bold leading-snug">
          <a
            href={~p"/priorities/#{@item.id}"}
            id={"item-card-link-#{@item.id}"}
            data-item-id={@item.id}
            phx-hook=".OpenItem"
            class="hover:underline"
          >
            {@item.title}
          </a>
        </h3>
        <span class="shrink-0 rounded-full bg-base-200 px-2 py-0.5 text-[0.65rem] font-semibold opacity-60">
          {item_type_label(@item.item_type)}
        </span>
      </div>

      <p :if={@show_category && Map.get(@item, :category)} class="text-xs opacity-60">
        {@item.category.name}
      </p>

      <div :if={match?(%{tags: [_ | _]}, @item)} class="flex flex-wrap gap-1">
        <.tag_chip :for={tag <- @item.tags} tag={tag} />
      </div>

      <div class="mt-auto space-y-1 pt-1">
        <.progress_summary progress={@progress} />
        <p class="flex items-center gap-1 text-xs opacity-50">
          <.icon name="hero-star-solid" class="size-3" />{@item.store_points}
        </p>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".OpenItem">
      export default {
        mounted() {
          this.el.addEventListener("click", (e) => {
            const wantsNewTab = e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1
            if (wantsNewTab) return

            e.preventDefault()
            this.pushEvent("open_item", {id: this.el.dataset.itemId})
          })
        }
      }
    </script>
    """
  end

  attr :progress, :any, required: true

  defp progress_summary(%{progress: {:streak, streak}} = assigns) do
    assigns = assign(assigns, :streak, streak)

    ~H"""
    <p class="flex items-center gap-1 text-xs font-semibold text-primary">
      <.icon name="hero-fire" class="size-4" />
      {@streak} {if @streak == 1, do: "dia seguido", else: "dias seguidos"}
    </p>
    """
  end

  defp progress_summary(%{progress: {:percent, nil}} = assigns) do
    ~H"""
    <p class="text-xs opacity-60">Sem progresso ainda</p>
    """
  end

  defp progress_summary(%{progress: {:percent, percent}} = assigns) do
    assigns = assign(assigns, :percent, percent)

    ~H"""
    <div class="space-y-1">
      <.progress_bar percent={@percent} />
      <p class="text-xs opacity-70">{@percent}%</p>
    </div>
    """
  end

  @doc """
  Torna seu conteúdo arrastável. Por padrão (`handle={false}`), o card
  inteiro vira a área de arrastar — exceto links, botões e campos de
  formulário lá dentro, que o SortableJS ignora como início de drag (ver
  `filter` em `drop_zone/1`), então continuam clicáveis normalmente (ex:
  clicar no título do card pra ver os detalhes do item). Passe
  `handle={true}` pra restringir o arrastar a um "grip" explícito — usado
  quando o conteúdo tem uma área interativa grande demais pra distinguir
  clique de arrastar só por elemento (ex: uma categoria inteira, com
  formulário e lista de itens dentro).
  """
  attr :id, :string, required: true
  attr :drag_id, :string, required: true
  attr :handle, :boolean, default: false
  slot :inner_block, required: true

  def draggable(assigns) do
    ~H"""
    <div
      id={@id}
      data-drag-id={@drag_id}
      class={[
        "relative",
        @handle && "group/drag",
        !@handle &&
          "cursor-grab touch-pan-y select-none [-webkit-touch-callout:none] active:cursor-grabbing"
      ]}
    >
      <button
        :if={@handle}
        type="button"
        data-drag-handle
        class="absolute -left-2 -top-2 z-10 grid size-6 cursor-grab touch-none select-none [-webkit-touch-callout:none] place-items-center rounded-full border border-base-300 bg-base-100 opacity-0 shadow-sm transition group-hover/drag:opacity-100 active:cursor-grabbing"
        title="Arrastar para reordenar"
      >
        <.icon name="hero-bars-2" class="size-3.5 opacity-60" />
      </button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Área que aceita soltar itens de um `draggable/1`, via SortableJS
  (`assets/vendor/sortable.js`, exposto como `window.Sortable` em `app.js`).
  Só troca item com outra `drop_zone/1` do mesmo `drag_group` — grupos
  diferentes não se aceitam, o que é o que impede, por exemplo, um item ser
  arrastado para a categoria errada (cada categoria tem seu próprio grupo,
  único).

  `mode="reorder"` reordena dentro da própria zona e envia a lista completa,
  na nova ordem, para `event` como `%{"zone_id" => value, "ordered_ids" => [...]}`.
  `mode="move"` (usado no board de tiers e na Tela do dia) não reordena — só
  manda pra onde o item foi solto, como `%{"id" => item_id, "value" => value}`.

  `handle={true}` precisa bater com o mesmo atributo nos `draggable/1` de
  dentro (ver ali) — é o que decide se o Sortable só inicia o arrastar pelo
  grip (`handle:`) ou pelo card inteiro, ignorando links/botões/campos
  (`filter:`).
  """
  attr :id, :string, required: true
  attr :drag_group, :string, required: true
  attr :mode, :string, values: ~w(reorder move), default: "reorder"
  attr :event, :string, required: true
  attr :value, :string, default: nil
  attr :handle, :boolean, default: false
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def drop_zone(assigns) do
    ~H"""
    <div
      id={@id}
      data-drag-group={@drag_group}
      data-drop-mode={@mode}
      data-drop-event={@event}
      data-drop-value={@value}
      data-drag-handle-mode={to_string(@handle)}
      phx-hook=".SortableZone"
      class={@class}
    >
      {render_slot(@inner_block)}
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SortableZone">
      export default {
        mounted() {
          const el = this.el
          const useHandle = el.dataset.dragHandleMode === "true"

          // Segurar o dedo pra arrastar é, pro navegador, o mesmo gesto de
          // abrir o menu de contexto (equivalente touch do botão direito).
          // `touch-action`/`-webkit-touch-callout` (ver classes do card em
          // `draggable/1`) já resolvem a maioria dos casos, mas alguns
          // navegadores Android ainda disparam `contextmenu` depois de um
          // "long press" mesmo assim — isso é o reforço final.
          el.addEventListener("contextmenu", (e) => e.preventDefault())

          this.sortable = new window.Sortable(el, {
            ...(useHandle
              ? {handle: "[data-drag-handle]"}
              : {filter: "a, button, input, textarea, select, label", preventOnFilter: false}),
            group: el.dataset.dragGroup,
            dataIdAttr: "data-drag-id",
            animation: 150,
            ghostClass: "opacity-40",
            // Sem isso, o Sortable usa a API nativa de drag-and-drop do
            // HTML5 pra mouse (só a parte touch é JS puro) — exatamente a
            // API frágil que motivou trocar pro Sortable. `forceFallback`
            // faz todo input (mouse, touch, caneta) passar pela
            // implementação própria dele, sem depender do navegador
            // reconhecer o gesto de arrastar.
            forceFallback: true,
            fallbackTolerance: 3,
            // No touch, um toque vira arrastar na hora — mesmo gesto de um
            // scroll comum. `delay` exige uma pausa antes de iniciar o
            // drag; `delayOnTouchOnly` restringe isso ao touch (mouse
            // continua instantâneo); `touchStartThreshold` cancela o
            // delay (e libera o scroll nativo) se o dedo já mover mais que
            // isso enquanto espera.
            delay: 150,
            delayOnTouchOnly: true,
            touchStartThreshold: 5,
            // `forceFallback` tira o autoscroll do caminho nativo de
            // `dragover` — sem `forceAutoScrollFallback` ele não engata
            // de forma confiável em touch, que era exatamente o sintoma
            // (arrastar um card até a borda da tela não rolava nada).
            scroll: true,
            forceAutoScrollFallback: true,
            scrollSensitivity: 80,
            scrollSpeed: 15,
            bubbleScroll: true,
            onEnd: (evt) => {
              const from = evt.from
              const to = evt.to

              if (from === to && evt.oldIndex === evt.newIndex) return

              if (to.dataset.dropMode === "move") {
                this.pushEvent(to.dataset.dropEvent, {
                  id: evt.item.dataset.dragId,
                  value: to.dataset.dropValue || ""
                })
              } else {
                const ids = Array.from(to.children).map((child) => child.dataset.dragId)

                this.pushEvent(to.dataset.dropEvent, {
                  zone_id: to.dataset.dropValue || "",
                  ordered_ids: ids
                })
              }
            }
          })
        },

        destroyed() {
          this.sortable?.destroy()
        }
      }
    </script>
    """
  end

  @doc "Rótulo em português de cada tipo de item, usado nos cartões e nos formulários."
  def item_type_label(:book), do: "Livro"
  def item_type_label(:quiz_goal), do: "Meta de quiz"
  def item_type_label(:course), do: "Curso"
  def item_type_label(:checklist), do: "Checklist"
  def item_type_label(:manual), do: "Manual"

  @doc "Opções `{label, value}` de tipo de item pro `<select>`, na ordem em que aparecem no form."
  def item_type_options do
    Enum.map(
      ~w(manual book quiz_goal course checklist)a,
      &{item_type_label(&1), Atom.to_string(&1)}
    )
  end

  @doc """
  Substitui um `<select multiple>` nativo: com várias opções (dias da
  semana, dias do mês), o listbox nativo não respeita a altura do `.select`
  do daisyUI e acaba maior que o próprio modal. Chips clicáveis (checkbox
  escondido + label estilizada) ficam do tamanho do conteúdo, sem esse
  problema, e continuam funcionando como formulário normal — o
  `name="...[]"` de cada opção marcada chega em `params` do mesmo jeito.
  Usado pelo form de frequência de hábito (captura do Kanban e
  `ActivityModal`).
  """
  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :selected, :list, required: true
  attr :class, :any, default: "flex flex-wrap gap-2"

  def day_toggle_group(assigns) do
    ~H"""
    <div class={@class}>
      <label
        :for={{label, value} <- @options}
        class="cursor-pointer select-none rounded-full border border-base-300 bg-base-100 px-3 py-1.5 text-center text-sm font-semibold opacity-70 transition hover:opacity-100 has-checked:border-primary has-checked:bg-primary has-checked:text-primary-content has-checked:opacity-100"
      >
        <input
          type="checkbox"
          name={@name}
          value={value}
          checked={to_string(value) in @selected}
          class="hidden"
        />
        {label}
      </label>
    </div>
    """
  end

  @doc """
  Seção "Hábito" completa (streak, arquivar/excluir, form de frequência) —
  compartilhada entre `ActivityModal` (quando a atividade aberta é uma
  instância de hábito) e `HabitModal` (aberto direto da tela "Próximos
  dias", sem nenhuma atividade de hoje pra ancorar). O host precisa
  implementar `handle_event/3` pros eventos usados aqui:
  `habit_frequency_form_change`, `set_habit_frequency`,
  `toggle_archive_habit`, `delete_habit` (sempre), e
  `save_occurrence_override`/`clear_occurrence_override` quando
  `allow_occurrence_edit?={true}`.

  `occurrence_date` é a data de referência do "essa e as próximas" — hoje,
  quando vem de `ActivityModal`, ou o dia clicado em "Próximos dias".
  `show_scope_choice?` só faz sentido pra uma data futura (a partir de
  hoje, "essa e as próximas" e "todas" têm o mesmo efeito, então
  `ActivityModal` nunca passa `true`).
  """
  attr :habit, :map, required: true
  attr :myself, :any, required: true
  attr :habit_streak, :integer, required: true
  attr :habit_frequency_form_value, :string, default: nil
  attr :occurrence_date, :any, required: true
  attr :show_scope_choice?, :boolean, default: false
  attr :allow_occurrence_edit?, :boolean, default: false
  attr :occurrence_override, :map, default: nil

  def habit_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="text-sm font-bold uppercase tracking-wide opacity-60">Hábito</h2>
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="toggle_archive_habit"
            phx-target={@myself}
            class="btn btn-soft btn-xs rounded-full"
            data-confirm={
              if @habit.archived_at,
                do: nil,
                else: "Arquivar este hábito? Ele para de gerar novas atividades."
            }
          >
            <.icon name="hero-archive-box" class="size-3.5" />
            {if @habit.archived_at, do: "Reativar", else: "Arquivar"}
          </button>
          <button
            type="button"
            phx-click="delete_habit"
            phx-target={@myself}
            class="btn btn-soft btn-xs rounded-full text-error"
            data-confirm="Excluir este hábito definitivamente? Atividades já feitas ficam soltas; isso não pode ser desfeito."
          >
            Excluir
          </button>
        </div>
      </div>

      <p class="flex items-center gap-2 text-sm font-semibold text-primary">
        <.icon name="hero-fire" class="size-5" />
        {@habit_streak} {if @habit_streak == 1, do: "dia seguido", else: "dias seguidos"}
      </p>

      <form
        id={"habit-store-points-form-#{@habit.id}"}
        phx-change="set_habit_store_points"
        phx-target={@myself}
        class="w-32"
      >
        <.input
          type="number"
          name="store_points"
          label="Pontos"
          value={@habit.store_points}
          min="0"
        />
      </form>

      <form
        id={"habit-frequency-form-#{@habit.id}"}
        phx-submit="set_habit_frequency"
        phx-change="habit_frequency_form_change"
        phx-target={@myself}
        class="space-y-3"
      >
        <.input
          type="select"
          name="frequency"
          label="Frequência"
          value={@habit_frequency_form_value || Atom.to_string(@habit.frequency)}
          options={[
            {"Diário", "daily"},
            {"Dias da semana", "weekly"},
            {"Dias do mês", "monthly"}
          ]}
        />

        <div
          :if={(@habit_frequency_form_value || Atom.to_string(@habit.frequency)) == "weekly"}
          class="fieldset mb-2"
        >
          <span class="label mb-1">Quais dias</span>
          <.day_toggle_group
            name="weekdays[]"
            selected={Enum.map(@habit.weekdays, &to_string/1)}
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

        <div
          :if={(@habit_frequency_form_value || Atom.to_string(@habit.frequency)) == "monthly"}
          class="fieldset mb-2"
        >
          <span class="label mb-1">Quais dias do mês</span>
          <.day_toggle_group
            name="month_days[]"
            selected={Enum.map(@habit.month_days, &to_string/1)}
            options={Enum.map(1..31, &{to_string(&1), to_string(&1)})}
            class="grid grid-cols-6 gap-1.5 sm:grid-cols-7"
          />
        </div>

        <div :if={@show_scope_choice?} class="fieldset mb-2">
          <span class="label mb-1">Aplicar em</span>
          <div class="flex flex-col gap-1.5 text-sm">
            <label class="flex items-center gap-2">
              <input type="radio" name="scope" value="all" class="radio radio-sm" checked />
              Todas as atividades
            </label>
            <label class="flex items-center gap-2">
              <input type="radio" name="scope" value="from_here" class="radio radio-sm" />
              Essa e as próximas (a partir de {Calendar.strftime(@occurrence_date, "%d/%m")})
            </label>
          </div>
        </div>

        <div class="flex justify-end">
          <button type="submit" class="btn btn-soft btn-sm rounded-full px-5">
            Salvar frequência
          </button>
        </div>
      </form>

      <form
        :if={@allow_occurrence_edit?}
        id={"habit-occurrence-form-#{@habit.id}-#{Date.to_iso8601(@occurrence_date)}"}
        phx-submit="save_occurrence_override"
        phx-target={@myself}
        class="space-y-3 border-t border-base-200 pt-3"
      >
        <p class="text-xs font-semibold uppercase tracking-wide opacity-50">
          Só {Calendar.strftime(@occurrence_date, "%d/%m")}
        </p>

        <.input
          type="text"
          name="title"
          label="Título só nesse dia (opcional)"
          value={@occurrence_override && @occurrence_override.title}
          placeholder={@habit.title}
        />

        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="skipped"
            value="true"
            checked={@occurrence_override && @occurrence_override.skipped}
            class="checkbox checkbox-sm"
          /> Pular esse dia
        </label>

        <div class="flex justify-end gap-2">
          <button
            :if={@occurrence_override}
            type="button"
            phx-click="clear_occurrence_override"
            phx-target={@myself}
            class="btn btn-ghost btn-sm rounded-full"
          >
            Remover exceção
          </button>
          <button type="submit" class="btn btn-soft btn-sm rounded-full px-5">
            Salvar exceção
          </button>
        </div>
      </form>
    </div>
    """
  end

  @doc "Sub-navegação entre as 5 telas de Prioridades, usada no topo de cada uma."
  attr :active, :atom, required: true

  def sub_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-sm font-semibold">
      <.link
        navigate={~p"/priorities"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :categories)
        ]}
      >
        Categorias
      </.link>
      <.link
        navigate={~p"/priorities/ranking"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :ranking)
        ]}
      >
        Prioridades misturadas
      </.link>
      <.link
        navigate={~p"/priorities/items"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :browse)
        ]}
      >
        Todos os itens
      </.link>
      <.link
        navigate={~p"/priorities/archived"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :archived)
        ]}
      >
        Arquivados
      </.link>
      <.link
        navigate={~p"/priorities/history"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :history)
        ]}
      >
        Histórico
      </.link>
    </nav>
    """
  end

  defp tab_class(true), do: "bg-primary text-primary-content shadow-sm"
  defp tab_class(false), do: "bg-base-200 opacity-70 hover:opacity-100"

  @doc "Sub-navegação entre as 3 telas do Kanban (Tela do dia / Próximos dias / Histórico), usada no topo de cada uma."
  attr :active, :atom, required: true

  def kanban_sub_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-sm font-semibold">
      <.link
        navigate={~p"/today"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :today)
        ]}
      >
        Hoje
      </.link>
      <.link
        navigate={~p"/today/upcoming"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :upcoming)
        ]}
      >
        Próximos dias
      </.link>
      <.link
        navigate={~p"/today/calendar"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :calendar)
        ]}
      >
        Calendário
      </.link>
    </nav>
    """
  end

  # Idade a partir da qual uma atividade solta acende alerta na Tela do dia —
  # âmbar cedo, vermelho só depois de ficar parada por mais tempo, pra não
  # virar papel de parede desde o primeiro dia.
  @warning_after_days 3
  @urgent_after_days 7

  @doc "Nível de alerta pela idade de `logical_date`, usado nas capturas soltas da Tela do dia."
  def age_alert(logical_date) do
    case Date.diff(Priorities.Clock.today(), logical_date) do
      days when days >= @urgent_after_days -> :urgent
      days when days >= @warning_after_days -> :warning
      _ -> :ok
    end
  end

  defp age_label(logical_date) do
    days = Date.diff(Priorities.Clock.today(), logical_date)
    "#{days} #{if days == 1, do: "dia", else: "dias"}"
  end

  @doc """
  Cartão de atividade da Tela do dia. `show_age?` liga o badge de alerta por
  idade (só faz sentido pra capturas soltas — atividade presa a um item pode
  ficar pendente por vários dias sem expirar; só a instância de hábito é
  sempre do dia). `actions` é opcional: cartões já resolvidos (`feito`) não
  recebem nenhuma.

  Sem raia por prioridade (ver moduledoc de `KanbanLive`), o que diferencia
  um card do outro é só visual: a borda lateral usa a cor da categoria do
  item/hábito associado (`Priorities.category_colors/1` já é usada com essa
  mesma paleta em `item_card/1`) e, se houver categoria, uma badge com o
  nome dela. Captura solta (sem item nem hábito) não tem nenhum dos dois.
  Evento (`kind == :evento`) usa a mesma cor de categoria, só que na borda
  direita em vez da esquerda — é a única marcação visual que diferencia um
  evento de uma tarefa comum, então precisa valer tanto presa a item quanto
  solta.
  """
  attr :activity, :map, required: true
  attr :show_age?, :boolean, default: false

  attr :clickable_title?, :boolean,
    default: true,
    doc: "false pro Calendário: consulta, não abre o modal de edição"

  slot :actions

  def activity_card(assigns) do
    assigns = assign(assigns, :category, activity_category(assigns.activity))

    ~H"""
    <div
      id={"activity-card-#{@activity.id}"}
      style={
        @category &&
          "border-#{card_border_side(@activity)}: 4px solid var(--color-#{elem(@category, 1)});"
      }
      class="card qcard mx-2 flex flex-col items-center gap-2 border border-base-300 bg-base-100 p-3 text-center"
    >
      <button
        :if={@clickable_title?}
        type="button"
        phx-click="open_activity"
        phx-value-id={@activity.id}
        class="line-clamp-2 text-center text-sm font-semibold leading-snug hover:underline"
      >
        {@activity.title}
      </button>
      <span
        :if={!@clickable_title?}
        class="line-clamp-2 text-center text-sm font-semibold leading-snug"
      >
        {@activity.title}
      </span>

      <span
        :if={@show_age? && age_alert(@activity.logical_date) != :ok}
        class={[
          "shrink-0 rounded-full px-2 py-0.5 text-[0.65rem] font-bold",
          age_alert(@activity.logical_date) == :urgent &&
            "bg-error text-error-content",
          age_alert(@activity.logical_date) == :warning &&
            "bg-warning text-warning-content"
        ]}
      >
        {age_label(@activity.logical_date)}
      </span>

      <span
        :if={@category && elem(@category, 0)}
        class="rounded-full bg-base-200 px-2 py-0.5 text-[0.65rem] font-semibold opacity-70"
      >
        {elem(@category, 0)}
      </span>

      <div class="flex w-full flex-wrap items-center justify-between gap-2 pt-1">
        <p class="flex items-center gap-1 text-[0.65rem] opacity-50">
          <.icon name="hero-star-solid" class="size-3" />{@activity.store_points}
        </p>
        <div :if={@actions != []} class="flex flex-wrap items-center justify-end gap-2">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  # `{nome_da_prioridade_ou_nil, token_de_cor_da_categoria}` do item/hábito
  # associado, ou `nil` pra captura solta. A cor (lateral do card) é sempre
  # a da categoria; o nome (badge) só aparece quando o item é uma
  # prioridade de verdade — o item "Geral" (categoria sem prioridade
  # específica) não tem nome pra mostrar, só a cor. Padrão de map (não
  # struct) casa igual com `Ash.NotLoaded` (relação não carregada) ou `nil`
  # (FK ausente) — os dois só caem no catch-all sem quebrar, então não
  # precisa checar qual dos dois é.
  defp card_border_side(%{kind: :evento}), do: "right"
  defp card_border_side(_activity), do: "left"

  defp activity_category(%{item: %{category: %{id: id}} = item}),
    do: {priority_badge_label(item), elem(category_colors(id), 0)}

  defp activity_category(%{habit: %{item: %{category: %{id: id}} = item}}),
    do: {priority_badge_label(item), elem(category_colors(id), 0)}

  defp activity_category(_activity), do: nil

  defp priority_badge_label(%{general: true}), do: nil
  defp priority_badge_label(%{title: title}), do: title
end
