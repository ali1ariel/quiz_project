defmodule QuizProject.Epub.Css do
  @moduledoc """
  Filtra a folha de estilo da editora para o leitor.

  A folha não é descartada — ela carrega semântica que não temos como
  reconstruir (o que é título de listagem, o que é fundo de código). Mas também
  não é aplicada crua: a deste livro tem 16 cores chapadas e `body { color:
  black }`, que no tema escuro vira texto preto sobre fundo preto.

  A política tem três colunas:

    * **descartar** — `@page`, regras em `body`/`html`, quebra de página,
      posicionamento: herança de paginação impressa;
    * **manter** — o que o editor decidiu e o tema não sabe (peso, caixa,
      alinhamento, bordas de tabela, ligaduras);
    * **traduzir** — cor e fundo viram token do tema, para a hierarquia visual
      sobreviver no claro e no escuro.

  Tudo sai escopado sob `.qreader-book`: nenhuma regra da editora alcança a
  navbar ou o resto da aplicação.
  """

  @scope ".qreader-book"

  # Fontes embutidas entram como data: URI na própria folha, servida por uma
  # rota com cache longo. Guardar o arquivo em disco custaria armazenamento e
  # rota de asset para 40KB que o navegador busca uma vez.
  @font_budget 400_000

  @keep ~w(
    font-style font-weight font-variant font-variant-ligatures font-feature-settings
    font-size-adjust text-decoration text-decoration-line text-decoration-style
    text-transform text-align text-indent white-space word-break overflow-wrap
    hyphens letter-spacing vertical-align quotes
    list-style list-style-type list-style-position
    counter-reset counter-increment
    border border-top border-right border-bottom border-left
    border-width border-style border-collapse border-spacing border-radius
  )

  @translate ~w(
    color background background-color border-color caret-color
    border-top-color border-right-color border-bottom-color border-left-color
    outline-color text-decoration-color column-rule-color fill stroke
  )

  # Seletores que só existiam porque o EPUB assume uma página de papel.
  @dropped_selectors ~w(body html :root @page)

  @doc """
  Folha pronta para o leitor, ou `nil` quando não sobra nada de aproveitável.

  `files` é o mapa `caminho => binário` do zip e `path` é onde a folha vive
  dentro dele, usado para resolver `url()` das fontes.
  """
  def filter(css, files \\ %{}, path \\ "") when is_binary(css) do
    rules = css |> strip_comments() |> parse()
    base = Path.dirname(path)

    {faces, families} = font_faces(rules, files, base)
    body = Enum.flat_map(rules, &render_rule(&1, families))

    case Enum.reject(faces ++ body, &(&1 == "")) do
      [] -> nil
      parts -> Enum.join(parts, "\n")
    end
  end

  # Regras

  defp render_rule({:rule, selector, declarations}, families) do
    with [_ | _] = selectors <- scope(selector),
         [_ | _] = kept <- Enum.flat_map(declarations, &render_declaration(&1, families)) do
      ["#{Enum.join(selectors, ",\n")} {\n  #{Enum.join(kept, "\n  ")}\n}"]
    else
      _ -> []
    end
  end

  # `@media print` descreve o livro impresso; o resto (largura de tela,
  # `prefers-*`) continua valendo dentro do leitor.
  defp render_rule({:at, "media", prelude, inner}, families) do
    if String.contains?(prelude, "print") do
      []
    else
      case Enum.flat_map(inner, &render_rule(&1, families)) do
        [] -> []
        parts -> ["@media #{prelude} {\n#{Enum.join(parts, "\n")}\n}"]
      end
    end
  end

  defp render_rule({:at, "supports", prelude, inner}, families) do
    case Enum.flat_map(inner, &render_rule(&1, families)) do
      [] -> []
      parts -> ["@supports #{prelude} {\n#{Enum.join(parts, "\n")}\n}"]
    end
  end

  defp render_rule(_other, _families), do: []

  defp scope(selector) do
    selector
    |> String.split(",")
    |> Enum.map(&squish/1)
    |> Enum.reject(&(&1 == "" or &1 in @dropped_selectors))
    |> Enum.map(fn one ->
      # `body p` vira `.qreader-book p`: a regra continua valendo para o texto
      # sem trazer junto a suposição de página.
      one
      |> String.replace(~r/\A(?:body|html)\b\s*/, "")
      |> squish()
      |> case do
        "" -> @scope
        rest -> @scope <> " " <> rest
      end
    end)
    |> Enum.uniq()
  end

  # Declarações

  defp render_declaration({property, value}, families) do
    value = value |> String.replace(~r/!\s*important/i, "") |> squish()

    cond do
      value == "" -> []
      property == "font-family" -> font_family(value, families)
      property in @translate -> translate(property, value)
      property in @keep -> ["#{property}: #{translate_inline_colors(value)};"]
      true -> []
    end
  end

  # A fonte de corpo da editora brigaria com a tipografia e o ajuste de tamanho
  # do leitor. A de código, não: quando o EPUB embute uma monoespaçada, ela é
  # escolha deliberada e sobrevive.
  defp font_family(value, families) do
    embedded? = Enum.any?(families, &String.contains?(String.downcase(value), &1))
    mono? = String.contains?(String.downcase(value), ["mono", "courier", "consolas"])

    if embedded? or mono?, do: ["font-family: #{value};"], else: []
  end

  defp translate(property, value) do
    case token(property, value) do
      :drop -> []
      token -> ["#{property}: #{token};"]
    end
  end

  # `background: #f2f2f2 no-repeat` mantém a parte não-cromática e troca a cor;
  # `url()` cai fora junto com as imagens, que estão fora da v1.
  defp token(property, value) do
    if String.contains?(value, "url(") do
      :drop
    else
      case color_in(value) do
        nil -> if property in ~w(color fill stroke), do: :drop, else: keep_keyword(value)
        color -> map_color(property, color)
      end
    end
  end

  defp keep_keyword(value) do
    if squish(value) in ~w(transparent none inherit currentColor), do: value, else: :drop
  end

  # Traduz cores dentro de valores compostos (`border: 1px solid #ccc`).
  defp translate_inline_colors(value) do
    case color_in(value) do
      nil ->
        value

      color ->
        replacement =
          case map_color("border-color", color) do
            :drop -> "currentColor"
            token -> token
          end

        String.replace(value, color.literal, replacement)
    end
  end

  # Cores → tokens do tema

  # A intenção que a editora codificou em cor é hierarquia: isto é destaque,
  # isto é fundo de código, isto é discreto. A tradução preserva o papel e
  # descarta a suposição de página branca fixa.
  defp map_color(property, %{luminance: l, saturation: s}) do
    cond do
      property in ~w(color fill stroke caret-color text-decoration-color) ->
        cond do
          # Texto claro só existe porque havia uma placa escura atrás dele.
          l > 0.7 -> "var(--color-primary-content)"
          s > 0.25 -> "var(--color-primary)"
          # Preto sobre branco é exatamente o que o tema já faz.
          true -> :drop
        end

      property in ~w(background background-color) ->
        cond do
          l > 0.88 and s < 0.2 -> "color-mix(in oklab, var(--color-base-content) 6%, transparent)"
          l > 0.6 -> "var(--color-base-200)"
          s > 0.25 -> "var(--color-primary)"
          true -> "var(--color-base-300)"
        end

      true ->
        if s > 0.25,
          do: "color-mix(in oklab, var(--color-primary) 45%, transparent)",
          else: "var(--color-base-300)"
    end
  end

  @named %{
    "black" => {0, 0, 0},
    "white" => {255, 255, 255},
    "silver" => {192, 192, 192},
    "gray" => {128, 128, 128},
    "grey" => {128, 128, 128},
    "red" => {255, 0, 0},
    "maroon" => {128, 0, 0},
    "green" => {0, 128, 0},
    "lime" => {0, 255, 0},
    "blue" => {0, 0, 255},
    "navy" => {0, 0, 128},
    "yellow" => {255, 255, 0},
    "orange" => {255, 165, 0},
    "purple" => {128, 0, 128},
    "teal" => {0, 128, 128},
    "aqua" => {0, 255, 255},
    "fuchsia" => {255, 0, 255},
    "olive" => {128, 128, 0}
  }

  defp color_in(value) do
    cond do
      match = Regex.run(~r/#[0-9a-fA-F]{3,8}\b/, value) -> hex(hd(match))
      match = Regex.run(~r/rgba?\([^)]*\)/i, value) -> rgb_fun(hd(match))
      named = named_in(value) -> named
      true -> nil
    end
  end

  defp named_in(value) do
    words = value |> String.downcase() |> String.split(~r/[^a-z]+/, trim: true)

    Enum.find_value(words, fn word ->
      case Map.fetch(@named, word) do
        {:ok, {r, g, b}} -> metrics(word, r, g, b)
        :error -> nil
      end
    end)
  end

  defp hex("#" <> digits = literal) do
    case String.length(digits) do
      n when n in [3, 4] ->
        [r, g, b] = digits |> String.slice(0, 3) |> String.graphemes() |> Enum.map(&pair/1)
        metrics(literal, r, g, b)

      n when n in [6, 8] ->
        [r, g, b] =
          digits |> String.slice(0, 6) |> chunk_pairs() |> Enum.map(&String.to_integer(&1, 16))

        metrics(literal, r, g, b)

      _ ->
        nil
    end
  end

  defp pair(digit), do: String.to_integer(digit <> digit, 16)

  defp chunk_pairs(string),
    do: string |> String.graphemes() |> Enum.chunk_every(2) |> Enum.map(&Enum.join/1)

  defp rgb_fun(literal) do
    literal
    |> String.replace(~r/rgba?\(|\)/i, "")
    |> String.split(~r/[,\s\/]+/, trim: true)
    |> Enum.take(3)
    |> Enum.map(&channel/1)
    |> case do
      [r, g, b] when is_integer(r) and is_integer(g) and is_integer(b) ->
        metrics(literal, r, g, b)

      _ ->
        nil
    end
  end

  defp channel(token) do
    cond do
      String.ends_with?(token, "%") ->
        token |> String.trim_trailing("%") |> to_number() |> then(&round(&1 * 255 / 100))

      true ->
        case Integer.parse(token) do
          {value, _} -> value
          :error -> nil
        end
    end
  end

  defp to_number(token) do
    case Float.parse(token) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp metrics(literal, r, g, b) do
    channels = [r, g, b]
    max = Enum.max(channels) / 255
    min = Enum.min(channels) / 255

    %{
      literal: literal,
      luminance: (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255,
      saturation: max - min
    }
  end

  # @font-face

  # A fonte vai embutida em base64 dentro da própria folha. Num livro com 76
  # listagens por capítulo a monoespaçada da editora é decisão tipográfica, e
  # ela não conflita com tema, tamanho nem largura de coluna.
  defp font_faces(rules, files, base) do
    rules
    |> Enum.filter(&match?({:at, "font-face", _, _}, &1))
    |> Enum.reduce({[], [], 0}, fn {:at, _, _, declarations}, {faces, families, spent} ->
      family = declaration(declarations, "font-family")
      source = declarations |> declaration("src") |> embed(files, base)

      case source do
        {:ok, url, size} when spent + size <= @font_budget ->
          face = """
          @font-face {
            font-family: #{family};
            font-style: #{declaration(declarations, "font-style") || "normal"};
            font-weight: #{declaration(declarations, "font-weight") || "normal"};
            font-display: swap;
            src: #{url};
          }\
          """

          {[face | faces], [normalize_family(family) | families], spent + size}

        _ ->
          {faces, families, spent}
      end
    end)
    |> then(fn {faces, families, _spent} -> {Enum.reverse(faces), families} end)
  end

  defp embed(nil, _files, _base), do: :error

  defp embed(src, files, base) do
    with [_, path] <- Regex.run(~r/url\(\s*['"]?([^'")]+)['"]?\s*\)/, src),
         resolved = resolve(base, path),
         {:ok, binary} <- Map.fetch(files, resolved) do
      mime = mime_type(resolved)

      {:ok, "url(data:#{mime};base64,#{Base.encode64(binary)}) format('#{format(resolved)}')",
       byte_size(binary)}
    else
      _ -> :error
    end
  end

  defp resolve(base, path) do
    base |> Path.join(path) |> Path.expand("/") |> String.trim_leading("/")
  end

  defp mime_type(path) do
    case Path.extname(path) do
      ".woff2" -> "font/woff2"
      ".woff" -> "font/woff"
      ".otf" -> "font/otf"
      _ -> "font/ttf"
    end
  end

  defp format(path) do
    case Path.extname(path) do
      ".woff2" -> "woff2"
      ".woff" -> "woff"
      ".otf" -> "opentype"
      _ -> "truetype"
    end
  end

  defp declaration(declarations, property) do
    Enum.find_value(declarations, fn
      {^property, value} -> value
      _ -> nil
    end)
  end

  defp normalize_family(nil), do: ""

  defp normalize_family(family) do
    family |> String.replace(~w(' "), "") |> String.downcase() |> squish()
  end

  # Parser

  defp strip_comments(css), do: String.replace(css, ~r|/\*.*?\*/|s, "")

  defp parse(css), do: parse(css, "", [])

  defp parse(<<>>, _prelude, acc), do: Enum.reverse(acc)

  defp parse(<<"{", rest::binary>>, prelude, acc) do
    {body, rest} = take_block(rest, 0, "")
    parse(rest, "", [build(squish(prelude), body) | acc])
  end

  # `@import` e `@charset` terminam em `;` sem bloco; nenhum dos dois entra.
  defp parse(<<";", rest::binary>>, _prelude, acc), do: parse(rest, "", acc)

  defp parse(<<char::utf8, rest::binary>>, prelude, acc),
    do: parse(rest, prelude <> <<char::utf8>>, acc)

  defp take_block(<<>>, _depth, acc), do: {acc, ""}

  defp take_block(<<"}", rest::binary>>, 0, acc), do: {acc, rest}

  defp take_block(<<"}", rest::binary>>, depth, acc),
    do: take_block(rest, depth - 1, acc <> "}")

  defp take_block(<<"{", rest::binary>>, depth, acc),
    do: take_block(rest, depth + 1, acc <> "{")

  defp take_block(<<char::utf8, rest::binary>>, depth, acc),
    do: take_block(rest, depth, acc <> <<char::utf8>>)

  defp build("@" <> at_rule = prelude, body) do
    name = at_rule |> String.split(~r/\s/, parts: 2) |> hd() |> String.downcase()
    rest = prelude |> String.replace_prefix("@" <> name, "") |> squish()

    if String.contains?(body, "{") do
      {:at, name, rest, parse(body, "", [])}
    else
      {:at, name, rest, declarations(body)}
    end
  end

  defp build(selector, body), do: {:rule, selector, declarations(body)}

  defp declarations(body) do
    body
    |> split_declarations()
    |> Enum.flat_map(fn declaration ->
      case String.split(declaration, ":", parts: 2) do
        [property, value] ->
          [{property |> squish() |> String.downcase(), squish(value)}]

        _ ->
          []
      end
    end)
  end

  # `;` dentro de `url(...)` ou de aspas não separa declaração.
  defp split_declarations(body) do
    ~r/;(?=(?:[^()"']|\([^)]*\)|"[^"]*"|'[^']*')*$)/
    |> Regex.split(body)
    |> Enum.map(&squish/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
end
