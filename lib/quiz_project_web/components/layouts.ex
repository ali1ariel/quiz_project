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

  attr :wide, :boolean, default: false, doc: "usa container largo para telas densas"

  attr :active_nav, :atom,
    default: nil,
    doc: "destino principal ativo: :quizzes ou :account"

  attr :attempt_started_at, :any,
    default: nil,
    doc: "início da tentativa em andamento; quando presente, exibe o cronômetro na navbar"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar sticky top-0 z-50 px-4 sm:px-6 lg:px-8 border-b border-base-300 bg-base-100/95 backdrop-blur min-h-14 gap-2">
      <div class="flex-1 min-w-0">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2 font-bold text-lg">
          <img src={~p"/images/logo.png"} alt="Quizzes" class="size-8 shrink-0 rounded-full" />
          <span class="md:hidden lg:inline">Quizzes</span>
        </.link>
      </div>

      <%!-- navegação completa (desktop) --%>
      <nav
        :if={@current_user}
        id="desktop-primary-nav"
        class="absolute left-1/2 hidden -translate-x-1/2 items-center gap-2 md:flex"
        aria-label="Navegação principal"
      >
        <%= if @active_nav == :quizzes do %>
          <span
            id="desktop-nav-quizzes"
            aria-current="page"
            class="inline-flex cursor-default items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-sm"
            title="Você está em Meus quizzes"
          >
            <.icon name="hero-rectangle-stack" class="size-4" /> Meus quizzes
          </span>
        <% else %>
          <.link
            id="desktop-nav-quizzes"
            navigate={~p"/painel"}
            class="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold opacity-65 transition hover:bg-base-200 hover:opacity-100"
            title="Criar, editar e acompanhar seus quizzes"
          >
            <.icon name="hero-rectangle-stack" class="size-4" /> Meus quizzes
          </.link>
        <% end %>

        <%= if @active_nav == :account do %>
          <span
            id="desktop-nav-account"
            aria-current="page"
            class="inline-flex cursor-default items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-sm"
            title="Você está em Conta e API"
          >
            <.icon name="hero-user-circle" class="size-4" /> Conta e API
          </span>
        <% else %>
          <.link
            id="desktop-nav-account"
            navigate={~p"/configuracoes"}
            class="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold opacity-65 transition hover:bg-base-200 hover:opacity-100"
            title="Alterar perfil, senha e tokens de integração"
          >
            <.icon name="hero-user-circle" class="size-4" /> Conta e API
          </.link>
        <% end %>
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
          <span class="hidden max-w-44 truncate text-sm opacity-65 xl:block">
            {@current_user.email}
          </span>
          <.link
            id="desktop-logout"
            href={~p"/sair"}
            method="delete"
            class="rounded-full border border-base-300 px-4 py-2 text-sm font-semibold transition hover:border-error/40 hover:bg-error/10 hover:text-error"
          >
            Sair
          </.link>
        <% else %>
          <.link navigate={~p"/entrar"} class="rounded-full px-4 py-2 text-sm font-semibold">
            Entrar
          </.link>
          <.link
            navigate={~p"/criar-conta"}
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
              <p class="text-xs opacity-60 truncate px-1">{@current_user.email}</p>
              <.link
                navigate={~p"/painel"}
                class="flex items-center gap-3 rounded-2xl border border-base-300 px-3 py-2.5 transition hover:border-primary hover:bg-base-100"
              >
                <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                  <.icon name="hero-rectangle-stack" class="size-4" />
                </span>
                <span class="min-w-0 text-left">
                  <span class="block text-sm font-semibold">Meus quizzes</span>
                  <span class="block truncate text-[0.68rem] opacity-55">
                    Criar, editar e acompanhar
                  </span>
                </span>
              </.link>
              <.link
                navigate={~p"/configuracoes"}
                class="flex items-center gap-3 rounded-2xl border border-transparent px-3 py-2.5 transition hover:border-base-300 hover:bg-base-100"
              >
                <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                  <.icon name="hero-user-circle" class="size-4" />
                </span>
                <span class="min-w-0 text-left">
                  <span class="block text-sm font-semibold">Conta e API</span>
                  <span class="block truncate text-[0.68rem] opacity-55">Perfil, senha e tokens</span>
                </span>
              </.link>
              <.link
                href={~p"/sair"}
                method="delete"
                class="btn btn-ghost btn-sm w-full rounded-full"
              >
                Sair
              </.link>
            <% else %>
              <.link navigate={~p"/entrar"} class="btn btn-outline btn-sm w-full rounded-full">
                Entrar
              </.link>
              <.link
                navigate={~p"/criar-conta"}
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
            <label class="text-xs opacity-60" for="skin-select-mobile">Estilo</label>
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
            <span class="text-xs opacity-60">Tema</span>
            <.theme_toggle />
          </div>
        </div>
      </details>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", if(@wide, do: "max-w-5xl", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
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
    <div id={@id} aria-live="polite">
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
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
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
