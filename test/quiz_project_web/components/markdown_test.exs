defmodule QuizProjectWeb.Components.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias QuizProjectWeb.Components.Markdown

  describe "markdown/1" do
    test "sem material_id, src relativo de imagem passa intacto" do
      html = render_component(&Markdown.markdown/1, content: "![alt](OEBPS/Images/a-arr.png)")

      assert html =~ ~s(src="OEBPS/Images/a-arr.png")
    end

    test "com material_id, reescreve src relativo para a rota de imagens do material" do
      html =
        render_component(&Markdown.markdown/1,
          content: "![alt](OEBPS/Images/a-arr.png)",
          material_id: "abc-123"
        )

      assert html =~ ~s(src="/contents/abc-123/images/OEBPS/Images/a-arr.png")
    end

    test "src absoluto ou com esquema não é reescrito mesmo com material_id" do
      html =
        render_component(&Markdown.markdown/1,
          content: "![alt](https://exemplo.com/a.png)",
          material_id: "abc-123"
        )

      assert html =~ ~s(src="https://exemplo.com/a.png")
    end
  end
end
