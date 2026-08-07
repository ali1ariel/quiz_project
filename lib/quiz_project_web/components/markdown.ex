defmodule QuizProjectWeb.Components.Markdown do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Renderiza uma string no formato Markdown como HTML seguro.
  """
  attr :content, :string, default: ""
  attr :class, :string, default: ""

  def markdown(assigns) do
    html =
      if assigns.content && assigns.content != "" do
        case MDEx.to_html(assigns.content) do
          {:ok, rendered} ->
            rendered

          _ ->
            assigns.content
            |> Phoenix.HTML.html_escape()
            |> Phoenix.HTML.safe_to_string()
        end
      else
        ""
      end

    assigns = assign(assigns, :html, html)

    ~H"""
    <div class={["prose prose-sm dark:prose-invert max-w-none break-words leading-relaxed", @class]}>
      {raw(@html)}
    </div>
    """
  end
end
