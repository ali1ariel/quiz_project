defmodule QuizProjectWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use QuizProjectWeb, :html

  embed_templates "page_html/*"

  attr :id, :string, required: true
  attr :method, :string, required: true
  attr :path, :string, required: true
  attr :scope, :string, default: nil
  attr :response, :string, required: true
  slot :inner_block, required: true

  def api_endpoint(assigns) do
    ~H"""
    <details id={@id} class="group overflow-hidden rounded-2xl border border-base-300 bg-base-100">
      <summary class="flex cursor-pointer list-none flex-col gap-3 p-4 marker:hidden sm:flex-row sm:items-center sm:p-5">
        <span class={[
          "w-fit rounded-lg px-2.5 py-1 font-mono text-xs font-bold",
          method_class(@method)
        ]}>
          {@method}
        </span>
        <code class="min-w-0 flex-1 break-all text-sm font-semibold sm:text-base">{@path}</code>
        <div class="flex items-center gap-2 text-xs opacity-70">
          <span :if={@scope} class="rounded-full border border-base-300 px-2.5 py-1">{@scope}</span>
          <span>{@response}</span>
          <.icon
            name="hero-chevron-down"
            class="size-4 transition-transform duration-200 group-open:rotate-180"
          />
        </div>
      </summary>
      <div class="space-y-5 border-t border-base-300 bg-base-200/45 p-4 sm:p-5">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :title, :string, required: true
  attr :name_label, :string, default: "Campo"
  attr :type_label, :string, default: "Tipo"
  attr :presence_label, :string, default: "Presença"

  slot :field, required: true do
    attr :name, :string, required: true
    attr :type, :string, required: true
    attr :presence, :string, required: true
  end

  def api_fields(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100">
      <div class="border-b border-base-300 px-4 py-3 text-xs font-bold uppercase tracking-[0.14em] opacity-70">
        {@title}
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[640px] text-left text-sm">
          <thead class="bg-base-200 text-xs opacity-70">
            <tr>
              <th class="px-4 py-3 font-semibold">{@name_label}</th>
              <th class="px-4 py-3 font-semibold">{@type_label}</th>
              <th class="px-4 py-3 font-semibold">{@presence_label}</th>
              <th class="px-4 py-3 font-semibold">Descrição</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300 align-top">
            <tr :for={field <- @field}>
              <td class="px-4 py-3"><code class="text-primary">{field.name}</code></td>
              <td class="px-4 py-3 font-mono text-xs">{field.type}</td>
              <td class="px-4 py-3 text-xs">{field.presence}</td>
              <td class="px-4 py-3 leading-6 opacity-75">{render_slot(field)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp method_class("GET"), do: "bg-success/15 text-success"
  defp method_class("POST"), do: "bg-info/15 text-info"
  defp method_class("PATCH"), do: "bg-warning/15 text-warning"
  defp method_class("DELETE"), do: "bg-error/15 text-error"
  defp method_class(_method), do: "bg-base-200 text-base-content"
end
