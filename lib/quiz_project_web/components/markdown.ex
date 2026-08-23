defmodule QuizProjectWeb.Components.Markdown do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Renderiza uma string no formato Markdown como HTML seguro.

  `material_id`, quando informado, reescreve `src` de imagem relativo (o
  caminho cru de dentro do EPUB, ex: `OEBPS/Images/a-arr.png`) para a URL de
  `BookImageController` — sem isso o navegador resolve o caminho relativo à
  página atual, não ao material a que a imagem pertence (mesmo mecanismo já
  usado pelo leitor do livro em `QuizProjectWeb.Components.Book`).
  """
  attr :content, :string, default: ""
  attr :class, :string, default: ""
  attr :material_id, :string, default: nil

  def markdown(assigns) do
    html =
      if assigns.content && assigns.content != "" do
        case MDEx.to_html(assigns.content) do
          {:ok, rendered} ->
            rewrite_images(rendered, assigns.material_id)

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
    <div class={["qprose", @class]}>
      {raw(@html)}
    </div>
    """
  end

  defp rewrite_images(html, nil), do: html

  defp rewrite_images(html, material_id) do
    Regex.replace(~r/src="(?!https?:|data:|\/)([^"]*)"/, html, fn _match, path ->
      ~s(src="/contents/#{material_id}/images/#{path}")
    end)
  end
end
