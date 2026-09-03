defmodule QuizProjectWeb.WishStoreLive.Components do
  @moduledoc """
  Componentes compartilhados entre as telas da Wish Store — hoje só a
  sub-navegação, mesmo padrão de `QuizProjectWeb.PrioritiesLive.Components.sub_nav/1`.
  """
  use QuizProjectWeb, :html

  @doc "Sub-navegação entre as telas da Wish Store (hoje só a Carteira)."
  attr :active, :atom, required: true

  def sub_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-sm font-semibold">
      <.link
        navigate={~p"/wish-store"}
        class={[
          "rounded-full px-4 py-1.5 transition [transform:translateZ(0)]",
          tab_class(@active == :wallet)
        ]}
      >
        Carteira
      </.link>
    </nav>
    """
  end

  defp tab_class(true), do: "bg-primary text-primary-content shadow-sm"
  defp tab_class(false), do: "bg-base-200 opacity-70 hover:opacity-100"
end
