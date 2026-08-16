defmodule QuizProjectWeb.Components.BookTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1, render_component: 2]

  alias QuizProjectWeb.Components.Book

  defp chapter(attrs) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        position: 1,
        level: 1,
        kind: :body,
        title: "",
        block_count: 0,
        estimated_tokens: 0
      },
      attrs
    )
  end

  defp render_contents(chapters, current) do
    %{chapters: chapters, current: current, material_id: "livro-1"}
    |> Book.contents()
    |> rendered_to_string()
  end

  defp block(attrs) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        position: 1,
        type: :paragraph,
        lang: nil,
        caption: nil,
        image_path: nil,
        content: "",
        annotations: []
      },
      attrs
    )
  end

  defp render_block(block) do
    render_component(&Book.block/1, %{block: block, material_id: "livro-1"})
  end

  describe "contents/1" do
    test "sumário achatado (todo nível 1) mantém a indentação de sempre" do
      capitulo = chapter(%{title: "1 O parafuso", level: 1})

      html = render_contents([capitulo], capitulo)

      assert html =~ "pl-3"
      refute html =~ "pl-6"
      refute html =~ "pl-9"
    end

    # Livro com Parte > Capítulo > Seção (ex.: "Machine Learning in Elixir")
    # não pode sair achatado — sem o recuo por nível, "Wrapping Up" repete a
    # cada capítulo sem nenhuma pista de qual seção é de qual.
    test "capítulo de segundo nível recua e reduz o texto" do
      parte = chapter(%{title: "Part II. Deep Learning", level: 1, position: 1})
      capitulo = chapter(%{title: "6. Go Deep with Axon", level: 2, position: 2})

      html = render_contents([parte, capitulo], parte)

      assert html =~ "pl-3"
      assert html =~ "pl-6"
    end

    test "seção de terceiro nível recua mais e fica mais discreta" do
      capitulo = chapter(%{title: "6. Go Deep with Axon", level: 2, position: 1})
      secao = chapter(%{title: "Wrapping Up", level: 3, position: 2})

      html = render_contents([capitulo, secao], capitulo)

      assert html =~ "pl-9"
      assert html =~ "text-xs"
    end

    test "pré-textual continua discreto independente do nível" do
      capa = chapter(%{title: "copyright", level: 1, kind: :front_matter})

      html = render_contents([capa], capa)

      assert html =~ "opacity-60"
    end
  end

  describe "tamanho do capítulo no sumário" do
    # O número ao lado do título era `block_count`, que conta um título de duas
    # palavras igual a uma listagem de 40 linhas. Token estimado mede esforço, e
    # é o mesmo número que o botão de IA mostra — duas medidas discordantes de
    # "tamanho" na mesma tela era o defeito.
    test "mostra os tokens estimados em forma curta" do
      capitulo = chapter(%{title: "1 O parafuso", estimated_tokens: 12_400, block_count: 3})

      html = render_contents([capitulo], capitulo)

      assert html =~ "12k"
      refute html =~ ">3<"
    end

    test "capítulo curto mostra o número cheio" do
      capitulo = chapter(%{title: "Prefácio", estimated_tokens: 340})

      html = render_contents([capitulo], capitulo)

      assert html =~ "340"
    end

    # Livro ingerido antes da coluna existir vale zero, e "0" ao lado do título
    # é ruído que parece capítulo vazio.
    test "capítulo sem estimativa não mostra número nenhum" do
      capitulo = chapter(%{title: "Sumário", estimated_tokens: 0})

      html = render_contents([capitulo], capitulo)

      refute html =~ "tabular-nums"
    end
  end

  describe "block/1 - :code" do
    # Livros costumam reproduzir o prompt do terminal junto com o comando —
    # útil impresso, mas quem cola o comando na própria linha de comando cola
    # o "$" junto e o shell recusa.
    test "remove o prompt de terminal (cifrão + espaço) do início de cada linha e do botão de copiar" do
      codigo =
        block(%{
          type: :code,
          lang: "bash",
          content: "$ asdf install elixir 1.14.3\n$ elixir --version"
        })

      html = render_block(codigo)

      assert html =~ "asdf install elixir 1.14.3"
      assert html =~ "elixir --version"
      refute html =~ "$ asdf"
      refute html =~ "$ elixir"
      assert html =~ ~s(data-copy="asdf install elixir 1.14.3\nelixir --version")
    end

    test "não mexe no cifrão que não abre a linha (variável de shell)" do
      codigo = block(%{type: :code, lang: "bash", content: "echo $HOME"})

      html = render_block(codigo)

      assert html =~ "echo $HOME"
    end

    test "traz um botão de copiar com o conteúdo já tratado" do
      codigo = block(%{type: :code, lang: "elixir", content: "IO.puts(\"oi\")"})

      html = render_block(codigo)

      assert html =~ "qreader-copy"
      assert html =~ "data-copy=\"IO.puts(&quot;oi&quot;)\""
    end
  end

  describe "block/1 - código inline no texto" do
    test "não remove o cifrão de dentro de um trecho de código inline" do
      texto = block(%{type: :paragraph, content: "Rode `$ mix test` para conferir."})

      html = render_block(texto)

      assert html =~ "<code>$ mix test</code>"
    end
  end
end
