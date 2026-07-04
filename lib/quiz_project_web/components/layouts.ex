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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 min-h-14 gap-2">
      <div class="flex-1 min-w-0">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2 font-bold text-lg">
          <span class="inline-flex items-center justify-center size-8 rounded-full bg-primary text-primary-content text-sm shrink-0">
            Q
          </span>
          Quizzes
        </.link>
      </div>

      <%!-- navegação completa (desktop) --%>
      <nav class="hidden md:block flex-none">
        <ul class="flex px-1 gap-2 items-center">
          <%= if @current_user do %>
            <li class="hidden lg:block text-sm opacity-70 mr-1 max-w-48 truncate">
              {@current_user.email}
            </li>
            <li>
              <.link navigate={~p"/painel"} class="btn btn-ghost btn-sm rounded-full">Painel</.link>
            </li>
            <li>
              <.link href={~p"/sair"} method="delete" class="btn btn-outline btn-sm rounded-full">
                Sair
              </.link>
            </li>
          <% else %>
            <li>
              <.link navigate={~p"/entrar"} class="btn btn-ghost btn-sm rounded-full">Entrar</.link>
            </li>
            <li>
              <.link navigate={~p"/criar-conta"} class="btn btn-primary btn-sm rounded-full">
                Criar conta
              </.link>
            </li>
          <% end %>
          <li>
            <.link href={~p"/api/docs"} class="btn btn-ghost btn-sm rounded-full">API</.link>
          </li>
          <li>
            <label class="sr-only" for="skin-select">Estilo visual</label>
            <select
              id="skin-select"
              data-skin-select
              phx-update="ignore"
              class="select select-sm rounded-full w-auto"
              title="Estilo visual"
            >
              <option value="tatil">Tátil 3D</option>
              <option value="sobrio">Sóbrio</option>
              <option value="classico">Clássico</option>
            </select>
          </li>
          <li><.theme_toggle /></li>
        </ul>
      </nav>

      <%!-- menu compacto (mobile) --%>
      <details class="dropdown dropdown-end md:hidden flex-none" id="mobile-menu">
        <summary class="btn btn-ghost btn-circle" aria-label="Abrir menu">
          <.icon name="hero-bars-3" class="size-6" />
        </summary>
        <div class="dropdown-content z-40 mt-3 w-64 max-w-[calc(100vw-2rem)] card qcard bg-base-200 p-4 space-y-4">
          <div class="space-y-2">
            <%= if @current_user do %>
              <p class="text-xs opacity-60 truncate px-1">{@current_user.email}</p>
              <.link navigate={~p"/painel"} class="btn btn-outline btn-sm w-full rounded-full">
                Painel
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
              Documentação da API
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
              <option value="tatil">Tátil 3D</option>
              <option value="sobrio">Sóbrio</option>
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

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
