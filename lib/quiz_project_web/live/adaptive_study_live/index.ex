defmodule QuizProjectWeb.AdaptiveStudyLive.Index do
  use QuizProjectWeb, :live_view

  alias QuizProject.AdaptiveStudy

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    materials = AdaptiveStudy.list_materials(user)

    {:ok,
     socket
     |> assign(
       page_title: "Estudo Adaptativo v2.0",
       materials: materials
     )}
  end

  @impl true
  def handle_event("delete_material", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case AdaptiveStudy.get_material(id, user) do
      {:ok, material} ->
        {:ok, _} = AdaptiveStudy.delete_material(material, user)
        materials = AdaptiveStudy.list_materials(user)

        {:noreply,
         socket
         |> put_flash(:info, "Material removido com sucesso.")
         |> assign(materials: materials)}

      _ ->
        {:noreply, put_flash(socket, :error, "Material não encontrado.")}
    end
  end

  @impl true
  def handle_info({:mindmap_generated, _info}, socket) do
    user = socket.assigns.current_user
    materials = AdaptiveStudy.list_materials(user)
    {:noreply, assign(socket, materials: materials)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:adaptive_study} wide={true}>
      <div class="space-y-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 border-b border-base-300 pb-5">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Estudo Adaptativo v2.0</h1>
            <p class="text-sm opacity-70 mt-1">
              Faça upload de conteúdos, gere Mapas Mentais atômicos e prepare seus materiais de estudo.
            </p>
          </div>
          <.link
            id="new-study-material-btn"
            navigate={~p"/adaptive-study/new"}
            class="btn btn-primary rounded-full px-5 inline-flex items-center gap-2"
          >
            <.icon name="hero-plus" class="size-5" /> Novo Material de Estudo
          </.link>
        </div>

        <%= if @materials == [] do %>
          <div class="rounded-3xl border-2 border-dashed border-base-300 p-12 text-center space-y-4 bg-base-200/50">
            <div class="grid size-16 place-items-center rounded-2xl bg-primary/10 text-primary mx-auto">
              <.icon name="hero-academic-cap" class="size-8" />
            </div>
            <div class="space-y-1">
              <h3 class="text-lg font-bold">Nenhum material de estudo cadastrado</h3>
              <p class="text-sm opacity-70 max-w-md mx-auto">
                Envie um texto bruto ou arquivo para gerar seu primeiro Mapa Mental atômico e iniciar a curadoria.
              </p>
            </div>
            <.link
              navigate={~p"/adaptive-study/new"}
              class="btn btn-primary rounded-full px-6 inline-flex items-center gap-2"
            >
              <.icon name="hero-arrow-up-tray" class="size-4" /> Inserir Primeiro Conteúdo
            </.link>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              :for={material <- @materials}
              id={"material-card-#{material.id}"}
              class="card qcard border border-base-300 bg-base-100 p-5 space-y-3 transition hover:shadow-md"
            >
              <div class="flex items-start justify-between gap-3">
                <span class={[
                  "badge badge-sm font-semibold rounded-full gap-1",
                  cond do
                    material.title == "Processando material..." -> "badge-info"
                    material.status == "curated" -> "badge-success"
                    true -> "badge-warning"
                  end
                ]}>
                  <%= if material.title == "Processando material..." do %>
                    <.icon name="hero-arrow-path" class="size-3 motion-safe:animate-spin" />
                    Processando com IA...
                  <% else %>
                    {if material.status == "curated", do: "Curado", else: "Rascunho"}
                  <% end %>
                </span>
                <button
                  id={"delete-material-#{material.id}"}
                  phx-click="delete_material"
                  phx-value-id={material.id}
                  data-confirm="Deseja realmente excluir este material de estudo?"
                  class="btn btn-ghost btn-xs text-error opacity-60 hover:opacity-100"
                  title="Excluir material"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>

              <div>
                <h2 class="text-lg font-bold leading-snug line-clamp-2">
                  {if material.title != "", do: material.title, else: "Sem título"}
                </h2>
                <p :if={material.summary != ""} class="text-xs opacity-75 mt-1 line-clamp-3">
                  {material.summary}
                </p>
              </div>

              <div class="pt-2 flex items-center justify-between border-t border-base-200 text-xs opacity-70">
                <span>Criado em {Calendar.strftime(material.inserted_at, "%d/%m/%Y às %H:%M")}</span>
                <.link
                  id={"curate-link-#{material.id}"}
                  navigate={~p"/adaptive-study/#{material.id}/curate"}
                  class="font-semibold text-primary inline-flex items-center gap-1 hover:underline"
                >
                  Ver Mapa Mental <.icon name="hero-arrow-right" class="size-3" />
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
