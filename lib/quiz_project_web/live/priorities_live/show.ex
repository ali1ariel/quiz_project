defmodule QuizProjectWeb.PrioritiesLive.Show do
  @moduledoc """
  Página cheia de um item de Prioridades — é o que abre quando o link do
  card é aberto numa aba nova (ver `Components.item_card/1`). Um clique
  normal, dentro do app, abre a mesma edição como modal em cima da
  categoria/ranking/listagem atual em vez de navegar pra cá; o conteúdo é o
  mesmo dos dois jeitos, vem de `PrioritiesLive.ItemModal` com
  `standalone={true}`.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Priorities
  alias QuizProjectWeb.PrioritiesLive.ItemModal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Priorities.get_item(id, socket.assigns.current_user) do
      {:ok, item} ->
        {:ok, assign(socket, page_title: item.title, item_id: id)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Item não encontrado.")
         |> push_navigate(to: ~p"/priorities")}
    end
  end

  @impl true
  def handle_info({:priorities_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:priorities}>
      <div class="mx-auto max-w-3xl space-y-6">
        <.link
          navigate={~p"/priorities"}
          class="flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3" /> Voltar a Prioridades
        </.link>

        <.live_component
          module={ItemModal}
          id={"item-modal-#{@item_id}"}
          item_id={@item_id}
          current_user={@current_user}
          standalone={true}
        />
      </div>
    </Layouts.app>
    """
  end
end
