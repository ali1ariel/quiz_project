defmodule QuizProjectWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use QuizProjectWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, :map, default: nil, doc: "usuário logado, se houver"

  attr :wide, :boolean,
    default: true,
    doc: "usa container largo (padrão); false volta pro estreito"

  attr :sticky_header?, :boolean,
    default: true,
    doc: "falso nas telas que já têm seu próprio header sticky (ex: leitura de conteúdos)"

  attr :active_nav, :atom,
    default: nil,
    doc:
      "destino principal ativo: :quizzes, :contents, :priorities, :kanban, :adaptive_study, :wish_store ou :account"

  attr :attempt_started_at, :any,
    default: nil,
    doc: "início da tentativa em andamento; quando presente, exibe o cronômetro na navbar"

  attr :notifications, :list,
    default: [],
    doc: "notificações fixas de execuções em background (assign do hook :notify_attempts)"

  attr :loose_captures_count, :integer,
    default: 0,
    doc: "capturas soltas sem definição (assign do hook :notify_loose_captures)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- `min-h-dvh` + coluna flex: o rodapé fica sempre no fim da tela, mesmo
         com pouco conteúdo — cresce com o `<main>` (`flex-1`) e só desce pela
         página de verdade quando o conteúdo passa da viewport. --%>
    <div class="flex min-h-dvh flex-col">
      <header class={[
        "navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-100/95 backdrop-blur min-h-14 gap-2 shrink-0",
        @sticky_header? && "sticky top-0 z-50"
      ]}>
        <div class="flex-1 min-w-0">
          <.link navigate={~p"/"} class="flex w-fit items-center gap-2 font-bold text-lg">
            <img src={~p"/images/logo.png"} alt="Quizzes" class="size-8 shrink-0 rounded-full" />
            <span class="md:hidden lg:inline">Quiz<span class="text-primary">zes</span></span>
          </.link>
        </div>

        <%!-- navegação completa (desktop) --%>
        <nav
          :if={@current_user}
          id="desktop-primary-nav"
          class="absolute left-1/2 hidden -translate-x-1/2 items-center gap-2 md:flex"
          aria-label="Navegação principal"
        >
          <%!-- O item ativo continua clicável, e não vira `<span>` estático: um
             menu com várias telas (Estudo Adaptativo, Conteúdos) é raiz de
             navegação própria, e clicar de novo nele é o atalho para voltar à
             raiz de onde se está, em vez de morrer sem fazer nada. --%>
          <.nav_item
            id="desktop-nav-quizzes"
            navigate={~p"/dashboard"}
            icon="hero-rectangle-stack"
            label="Meus quizzes"
            active?={@active_nav == :quizzes}
            title_active="Voltar para Meus quizzes"
            title_inactive="Criar, editar e acompanhar seus quizzes"
          />

          <.nav_item
            id="desktop-nav-contents"
            navigate={~p"/contents"}
            icon="hero-book-open"
            label="Conteúdos"
            active?={@active_nav == :contents}
            title_active="Voltar para a biblioteca de Conteúdos"
            title_inactive="Sua biblioteca de livros, focada na leitura"
          />

          <.nav_item
            id="desktop-nav-priorities"
            navigate={~p"/priorities"}
            icon="hero-flag"
            label="Prioridades"
            active?={@active_nav == :priorities}
            title_active="Voltar para Prioridades"
            title_inactive="Categorias, itens e evolução pessoal"
          />

          <.nav_item
            id="desktop-nav-kanban"
            navigate={~p"/today"}
            icon="hero-view-columns"
            label="Kanban"
            active?={@active_nav == :kanban}
            title_active="Voltar para o Kanban"
            title_inactive="Raias por prioridade, com o que é hoje"
            badge={@loose_captures_count}
          />

          <.nav_item
            id="desktop-nav-adaptive-study"
            navigate={~p"/study"}
            icon="hero-academic-cap"
            label="Estudo Adaptativo"
            active?={@active_nav == :adaptive_study}
            title_active="Voltar para a lista de Estudo Adaptativo"
            title_inactive="Ingestão e curadoria de materiais de estudo com Mapa Mental"
          />

          <.nav_item
            id="desktop-nav-wish-store"
            navigate={~p"/wish-store"}
            icon="hero-gift"
            label="Wish Store"
            active?={@active_nav == :wish_store}
            title_active="Voltar para a Wish Store"
            title_inactive="Carteira de pontos e recompensas"
          />
        </nav>

        <%!-- cronômetro da tentativa (todas as larguras) --%>
        <div
          :if={@attempt_started_at}
          id="attempt-timer"
          phx-hook=".AttemptTimer"
          phx-update="ignore"
          data-elapsed={DateTime.diff(DateTime.utc_now(), @attempt_started_at)}
          class="flex-none"
        >
          <button
            type="button"
            data-timer-toggle
            class="inline-flex h-10 items-center gap-2 rounded-full border border-base-300 px-3 text-sm font-semibold transition hover:border-primary hover:text-primary"
            aria-pressed="false"
            aria-label="Mostrar ou ocultar o cronômetro da tentativa"
            title="Cronômetro da tentativa"
          >
            <.icon name="hero-clock" class="size-5" />
            <span data-timer-value class="hidden font-mono tabular-nums">00:00</span>
          </button>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".AttemptTimer">
          export default {
            mounted() {
              // Âncora no relógio local a partir do tempo decorrido calculado no
              // servidor, imune a fuso/desvio de relógio do participante.
              this.base = Date.now() - parseInt(this.el.dataset.elapsed, 10) * 1000
              this.value = this.el.querySelector("[data-timer-value]")
              this.toggle = this.el.querySelector("[data-timer-toggle]")
              this.toggle.addEventListener("click", () => {
                const hidden = this.value.classList.toggle("hidden")
                this.toggle.setAttribute("aria-pressed", String(!hidden))
              })
              this.tick()
              this.interval = setInterval(() => this.tick(), 1000)
            },
            destroyed() {
              clearInterval(this.interval)
            },
            tick() {
              const total = Math.max(0, Math.floor((Date.now() - this.base) / 1000))
              const h = Math.floor(total / 3600)
              const m = Math.floor((total % 3600) / 60)
              const s = total % 60
              const pad = (n) => String(n).padStart(2, "0")
              this.value.textContent =
                h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
            }
          }
        </script>

        <%!-- conta e aparência (desktop) --%>
        <div class="hidden flex-none items-center justify-end gap-2 md:flex">
          <%= if @current_user do %>
            <%!-- E-mail e ícone no mesmo botão: ao passar o mouse, o e-mail cede
               lugar ao rótulo da ação ("Configurações de conta") em vez de um
               `title` nativo — junto no mesmo elemento, o hover explica o que
               o clique faz sem precisar de um segundo alvo separado. --%>
            <.link
              id="desktop-nav-account"
              navigate={~p"/settings"}
              aria-current={@active_nav == :account && "page"}
              aria-label="Configurações de conta"
              class={[
                "group inline-flex items-center gap-2 rounded-full py-2 pl-3 pr-4 text-sm font-semibold transition",
                if(@active_nav == :account,
                  do: "bg-primary text-primary-content shadow-sm",
                  else: "opacity-65 hover:bg-base-200 hover:opacity-100"
                )
              ]}
            >
              <.icon name="hero-user-circle" class="size-5 shrink-0" />
              <span class="hidden max-w-44 truncate xl:block">
                <span class="group-hover:hidden">{@current_user.email}</span>
                <span class="hidden group-hover:inline">Configurações de conta</span>
              </span>
            </.link>
            <.link
              id="desktop-logout"
              href={~p"/logout"}
              method="delete"
              class="rounded-full border border-base-300 px-4 py-2 text-sm font-semibold transition hover:border-error/40 hover:bg-error/10 hover:text-error"
            >
              Sair
            </.link>
          <% else %>
            <.link navigate={~p"/login"} class="rounded-full px-4 py-2 text-sm font-semibold">
              Entrar
            </.link>
            <.link
              navigate={~p"/register"}
              class="rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content"
            >
              Criar conta
            </.link>
          <% end %>
          <.appearance_control />
        </div>

        <%!-- menu compacto (mobile) --%>
        <details class="dropdown dropdown-end md:hidden flex-none" id="mobile-menu">
          <summary class="btn btn-ghost btn-circle" aria-label="Abrir menu">
            <.icon name="hero-bars-3" class="size-6" />
          </summary>
          <div class="dropdown-content z-40 mt-3 w-64 max-w-[calc(100vw-2rem)] card qcard bg-base-200 p-4 space-y-4">
            <div class="space-y-2">
              <%= if @current_user do %>
                <p class="text-xs opacity-70 truncate px-1">{@current_user.email}</p>
                <.link
                  navigate={~p"/dashboard"}
                  class="flex items-center gap-3 rounded-2xl border border-base-300 px-3 py-2.5 transition hover:border-primary hover:bg-base-100"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-rectangle-stack" class="size-4" />
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Meus quizzes</span>
                    <span class="block truncate text-[0.68rem] opacity-70">
                      Criar, editar e acompanhar
                    </span>
                  </span>
                </.link>
                <.link
                  navigate={~p"/contents"}
                  class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-book-open" class="size-4" />
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Conteúdos</span>
                    <span class="block truncate text-[0.68rem] opacity-70">Biblioteca e leitura</span>
                  </span>
                </.link>
                <.link
                  navigate={~p"/priorities"}
                  class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-flag" class="size-4" />
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Prioridades</span>
                    <span class="block truncate text-[0.68rem] opacity-70">
                      Categorias, itens e evolução
                    </span>
                  </span>
                </.link>
                <.link
                  navigate={~p"/today"}
                  class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
                >
                  <span class="relative grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-view-columns" class="size-4" />
                    <span
                      :if={@loose_captures_count > 0}
                      class="absolute -right-1 -top-1 inline-flex min-w-4 items-center justify-center rounded-full bg-error px-1 text-[0.6rem] font-bold text-error-content"
                    >
                      {@loose_captures_count}
                    </span>
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Kanban</span>
                    <span class="block truncate text-[0.68rem] opacity-70">
                      Raias por prioridade, hoje
                    </span>
                  </span>
                </.link>
                <.link
                  navigate={~p"/wish-store"}
                  class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-gift" class="size-4" />
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Wish Store</span>
                    <span class="block truncate text-[0.68rem] opacity-70">
                      Carteira de pontos e recompensas
                    </span>
                  </span>
                </.link>
                <.link
                  navigate={~p"/settings"}
                  class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                    <.icon name="hero-user-circle" class="size-4" />
                  </span>
                  <span class="min-w-0 text-left">
                    <span class="block text-sm font-semibold">Conta e API</span>
                    <span class="block truncate text-[0.68rem] opacity-70">Perfil, senha e tokens</span>
                  </span>
                </.link>
                <.link
                  href={~p"/logout"}
                  method="delete"
                  class="btn btn-ghost btn-sm w-full rounded-full"
                >
                  Sair
                </.link>
              <% else %>
                <.link navigate={~p"/login"} class="btn btn-outline btn-sm w-full rounded-full">
                  Entrar
                </.link>
                <.link
                  navigate={~p"/register"}
                  class="btn btn-primary btn-sm w-full rounded-full"
                >
                  Criar conta
                </.link>
              <% end %>
              <.link href={~p"/api/docs"} class="btn btn-ghost btn-sm w-full rounded-full">
                Docs para desenvolvedores
              </.link>
            </div>

            <div class="flex items-center justify-between gap-3">
              <label class="text-xs opacity-70" for="skin-select-mobile">Estilo</label>
              <select
                id="skin-select-mobile"
                data-skin-select
                phx-update="ignore"
                class="select select-sm rounded-full w-auto"
              >
                <option value="sobrio">Sóbrio</option>
                <option value="aurora">Aurora</option>
                <option value="classico">Clássico</option>
              </select>
            </div>

            <div class="flex items-center justify-between gap-3">
              <span class="text-xs opacity-70">Tema</span>
              <.theme_toggle />
            </div>
          </div>
        </details>
      </header>

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <div class={["mx-auto space-y-4", if(@wide, do: "qlayout-wide", else: "max-w-2xl")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="shrink-0 border-t border-base-300 px-4 py-6 text-center text-xs opacity-60 sm:px-6 lg:px-8">
        <.link navigate={~p"/privacy"} class="hover:underline">Privacidade</.link>
        <span class="px-2">·</span>
        <.link navigate={~p"/terms"} class="hover:underline">Termos de Serviço</.link>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    <.notification_stack notifications={@notifications} />
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active?, :boolean, required: true
  attr :title_active, :string, required: true
  attr :title_inactive, :string, required: true
  attr :badge, :integer, default: nil

  # Item da navegação principal. Continua `<.link>` ativo ou não — só a
  # aparência e o `title` mudam — porque a raiz de cada menu também precisa
  # de destino quando já se está nela.
  defp nav_item(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      aria-current={@active? && "page"}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition [transform:translateZ(0)]",
        if(@active?,
          do: "bg-primary text-primary-content shadow-sm",
          else: "opacity-65 hover:bg-base-200 hover:opacity-100"
        )
      ]}
      title={if @active?, do: @title_active, else: @title_inactive}
    >
      <.icon name={@icon} class="size-4" /> {@label}
      <span
        :if={@badge && @badge > 0}
        class="ml-0.5 inline-flex min-w-4 items-center justify-center rounded-full bg-error px-1 text-[0.65rem] font-bold text-error-content"
      >
        {@badge}
      </span>
    </.link>
    """
  end

  @doc """
  Pilha fixa de notificações de execuções em background (canto inferior
  direito). Persistem entre páginas e recargas até serem dispensadas ou
  abertas; os eventos são tratados pelo hook `:notify_attempts`.
  """
  attr :notifications, :list, required: true

  def notification_stack(assigns) do
    ~H"""
    <div
      :if={@notifications != []}
      id="notification-stack"
      class="fixed bottom-4 right-4 z-50 flex w-80 max-w-[calc(100vw-2rem)] flex-col gap-2"
      aria-live="polite"
      aria-label="Notificações"
    >
      <div
        :for={notification <- @notifications}
        id={"notification-#{notification.id}"}
        class="rounded-2xl border border-base-300 bg-base-100 p-3 shadow-lg space-y-1"
      >
        <div class="flex items-start justify-between gap-2">
          <p class="text-sm font-semibold flex items-center gap-1.5 min-w-0">
            <.icon name="hero-bell-alert" class="size-4 shrink-0 text-primary" />
            <span class="break-words">{notification.title}</span>
          </p>
          <button
            id={"dismiss-notification-#{notification.id}"}
            phx-click="dismiss_notification"
            phx-value-id={notification.id}
            class="btn btn-ghost btn-xs btn-circle shrink-0"
            aria-label="Dispensar notificação"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        <p :if={notification.body} class="text-xs opacity-70">{notification.body}</p>
        <button
          id={"open-notification-#{notification.id}"}
          phx-click="open_notification"
          phx-value-id={notification.id}
          class="text-sm font-semibold text-primary underline decoration-primary/35 underline-offset-2 hover:decoration-primary"
        >
          Clique aqui para ver o resultado
        </button>
      </div>
    </div>
    """
  end

  @doc "Controle compacto de aparência que se expande horizontalmente."
  def appearance_control(assigns) do
    ~H"""
    <div
      id="appearance-control"
      class="group relative h-10 w-10 shrink-0 overflow-hidden rounded-full transition-[width] duration-300 ease-out hover:w-[16rem] focus-within:w-[16rem]"
    >
      <div class="absolute inset-y-0 right-0 flex w-[16rem] flex-row-reverse items-center gap-2 rounded-full border border-base-300 bg-base-100 p-1 shadow-sm">
        <button
          id="appearance-trigger"
          type="button"
          class="grid size-8 shrink-0 place-items-center rounded-full text-base-content/65 transition group-hover:bg-primary/10 group-hover:text-primary group-focus-within:bg-primary/10 group-focus-within:text-primary"
          aria-label="Abrir controles de aparência"
          title="Aparência"
        >
          <.icon name="hero-swatch" class="size-5" />
        </button>

        <div class="invisible flex min-w-0 flex-1 items-center justify-end gap-2 opacity-0 transition-opacity duration-200 group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100">
          <label class="sr-only" for="skin-select">Estilo visual</label>
          <select
            id="skin-select"
            data-skin-select
            phx-update="ignore"
            class="h-8 w-24 rounded-full border border-base-300 bg-base-100 px-2 text-xs font-medium outline-none transition focus:border-primary"
            title="Estilo visual"
          >
            <option value="sobrio">Sóbrio</option>
            <option value="aurora">Aurora</option>
            <option value="classico">Clássico</option>
          </select>
          <span class="h-5 w-px bg-base-300"></span>
          <.theme_toggle />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed left-3 right-3 top-16 z-40 flex flex-col gap-2 sm:left-auto sm:right-4 sm:w-80"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  The appearance preferences are applied by assets/js/app.js.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center overflow-hidden border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Usar tema do sistema"
        title="Sistema"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Usar tema claro"
        title="Claro"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Usar tema escuro"
        title="Escuro"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
