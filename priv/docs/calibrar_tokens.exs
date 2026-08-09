# Calibra a estimativa de tokens contra a contagem real da Anthropic.
#
# O endpoint `count_tokens` é exato e não cobra geração, então dá para medir o
# livro inteiro de graça. Os pesos em `QuizProject.AdaptiveStudy.Books`
# (`@chars_per_token`) saíram de aproximações de tokenizador BPE, não de
# medição — este script diz o quanto elas erram, e para que lado.
#
#     ANTHROPIC_API_KEY=sk-... mix run priv/docs/calibrar_tokens.exs
#
# Opcionalmente, um `.epub` específico:
#
#     ANTHROPIC_API_KEY=sk-... mix run priv/docs/calibrar_tokens.exs ~/Downloads/livro.epub

require Ash.Query

alias QuizProject.AdaptiveStudy.Books
alias QuizProject.AdaptiveStudy.Chapter
alias QuizProject.AdaptiveStudy.StudyMaterial

defmodule Calibragem do
  @endpoint "https://api.anthropic.com/v1/messages/count_tokens"
  @model "claude-opus-5"

  def contar(texto, chave) do
    Req.post(@endpoint,
      headers: [
        {"x-api-key", chave},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ],
      json: %{model: @model, messages: [%{role: "user", content: texto}]},
      receive_timeout: 60_000
    )
    |> case do
      {:ok, %{status: 200, body: %{"input_tokens" => tokens}}} -> {:ok, tokens}
      {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def capitulos_do_banco do
    material =
      StudyMaterial
      |> Ash.Query.filter(format == :epub)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)

    if material do
      capitulos =
        Chapter
        |> Ash.Query.filter(material_id == ^material.id and kind == :body)
        |> Ash.Query.sort(position: :asc)
        |> Ash.read!(authorize?: false)

      {material.title, Enum.map(capitulos, &{&1.title, &1.estimated_tokens, texto(&1)})}
    end
  end

  def capitulos_do_arquivo(caminho) do
    {:ok, book} = caminho |> Path.expand() |> File.read!() |> QuizProject.Epub.parse()

    capitulos =
      book.chapters
      |> Enum.filter(&(&1.kind == :body))
      |> Enum.map(fn c ->
        {c.title, Books.estimate_tokens(c.blocks), Enum.map_join(c.blocks, "\n\n", & &1.content)}
      end)

    {book.title, capitulos}
  end

  defp texto(chapter), do: Books.chapter_text(chapter.id)
end

chave = System.get_env("ANTHROPIC_API_KEY")

if is_nil(chave) do
  IO.puts("""
  Faltou a chave.

      ANTHROPIC_API_KEY=sk-... mix run priv/docs/calibrar_tokens.exs
  """)

  System.halt(1)
end

{titulo, capitulos} =
  case System.argv() do
    [caminho | _] -> Calibragem.capitulos_do_arquivo(caminho)
    [] -> Calibragem.capitulos_do_banco() || {nil, []}
  end

if capitulos == [] do
  IO.puts("Nenhum livro para medir. Ingira um EPUB ou passe o caminho de um `.epub`.")
  System.halt(1)
end

IO.puts("\n== #{titulo} — #{length(capitulos)} capítulos de corpo ==\n")
IO.puts("capítulo                                   estimado      real     erro")

resultados =
  Enum.flat_map(capitulos, fn {nome, estimado, texto} ->
    case Calibragem.contar(texto, chave) do
      {:ok, real} ->
        erro = (estimado - real) / max(real, 1) * 100

        IO.puts(
          "#{String.pad_trailing(String.slice(nome, 0, 40), 42)}" <>
            "#{String.pad_leading(to_string(estimado), 9)}" <>
            "#{String.pad_leading(to_string(real), 10)}" <>
            "#{String.pad_leading("#{Float.round(erro, 1)}%", 9)}"
        )

        [{estimado, real}]

      {:error, motivo} ->
        IO.puts("#{String.pad_trailing(String.slice(nome, 0, 40), 42)}  falhou: #{motivo}")
        []
    end
  end)

if resultados != [] do
  soma_est = Enum.reduce(resultados, 0, fn {e, _}, a -> e + a end)
  soma_real = Enum.reduce(resultados, 0, fn {_, r}, a -> r + a end)
  erros = Enum.map(resultados, fn {e, r} -> abs(e - r) / max(r, 1) * 100 end)

  IO.puts("""

  total estimado ..... #{soma_est}
  total real ......... #{soma_real}
  desvio agregado .... #{Float.round((soma_est - soma_real) / max(soma_real, 1) * 100, 1)}%
  erro médio ......... #{Float.round(Enum.sum(erros) / length(erros), 1)}%
  pior capítulo ...... #{Float.round(Enum.max(erros), 1)}%

  Se o desvio agregado for consistente, ajuste `@chars_per_token` e
  `@chars_per_token_default` em lib/quiz_project/adaptive_study/books.ex
  dividindo os pesos atuais por (1 + desvio/100).
  """)
end
