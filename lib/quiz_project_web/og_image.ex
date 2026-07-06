defmodule QuizProjectWeb.OgImage do
  @moduledoc """
  Gera o card de preview de link (Open Graph, 1200×630) da tela de resultado.

  O HTML é montado aqui e rasterizado pelo Chrome headless via ChromicPDF. O
  resultado de uma tentativa pode mudar (anulação retroativa), então o cache é
  chaveado pelo conteúdo visível — some quando a nota muda. Em qualquer falha
  de render, quem chama serve o `fallback_png/0` estático (200), para o crawler
  nunca receber erro.

  Tema fixo: skin sobrio, claro — o que um usuário deslogado vê.
  """

  alias QuizProject.Attempts
  alias QuizProjectWeb.CoreComponents

  @width 1200
  @height 630

  @doc """
  PNG do card de resultado de uma tentativa finalizada, ou `:error` se a
  tentativa não existir, não estiver finalizada ou o render falhar.
  """
  def result_png(id) do
    with {:ok, attempt} <- fetch_finished(id) do
      summary = Attempts.result_summary(attempt)
      html = build_result_html(attempt, summary)
      cache_key = "og-#{attempt.id}-#{:erlang.phash2({attempt.score, attempt.percent, summary})}"

      cached(cache_key, fn -> render_png(html) end)
    end
  end

  @doc "PNG estático de fallback (card genérico), lido do disco uma única vez."
  def fallback_png do
    :persistent_term.get({__MODULE__, :fallback}, nil) || load_fallback()
  end

  @doc "Rasteriza um HTML completo em PNG 1200×630. Público para verificação."
  def render_png(html) do
    ChromicPDF.capture_screenshot({:html, html},
      capture_screenshot: %{
        format: "png",
        clip: %{x: 0, y: 0, width: @width, height: @height, scale: 1},
        captureBeyondViewport: true
      }
    )
    |> case do
      {:ok, base64} -> {:ok, Base.decode64!(base64)}
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  ## Interno

  defp fetch_finished(id) do
    attempt = Attempts.get_attempt_full!(id)
    if attempt.status == :finished, do: {:ok, attempt}, else: :error
  rescue
    _ -> :error
  end

  defp cached(key, fun) do
    path = Path.join(cache_dir(), key <> ".png")

    case File.read(path) do
      {:ok, png} ->
        {:ok, png}

      _ ->
        with {:ok, png} <- fun.() do
          File.mkdir_p(cache_dir())
          File.write(path, png)
          {:ok, png}
        end
    end
  end

  defp cache_dir do
    Application.get_env(:quiz_project, :og_cache_dir) ||
      Path.join(System.tmp_dir!(), "quiz_og_cache")
  end

  defp load_fallback do
    png = File.read!(Application.app_dir(:quiz_project, "priv/static/images/og-fallback.png"))
    :persistent_term.put({__MODULE__, :fallback}, png)
    png
  end

  # Card de resultado (skin sobrio, claro). Espelha o mock aprovado.
  defp build_result_html(attempt, s) do
    name = attempt.quiz_version.name |> to_string() |> truncate(58)
    duration = CoreComponents.format_duration(attempt.started_at, attempt.finished_at)

    rows = [
      {"Respondidas", "#{s.answered}/#{s.total}", nil},
      {"Acertos", "#{s.correct}", "ok"},
      {"Erros", "#{s.incorrect}", "err"},
      {"Parcialmente corretas", "#{s.partial}", "warn"},
      {~s("Não sei"), "#{s.dont_know}", nil},
      {"Questões anuladas", "#{s.annulled}", nil},
      {"Discursivas por IA", "#{s.ai_graded}", nil},
      {"Respostas importadas", "#{s.imported}", nil}
    ]

    rows_html =
      Enum.map_join(rows, "\n", fn {label, value, cls} ->
        val_class = if cls, do: "val #{cls}", else: "val"

        ~s(<div class="row"><span class="lbl">#{esc(label)}</span><span class="#{val_class}">#{esc(value)}</span></div>)
      end)

    """
    <!doctype html><html lang="pt-BR"><head><meta charset="utf-8" />
    <style>
      :root { --base-200:#ffffff; --content:#1b2430; --primary:#2f6bab;
        --success:#168147; --error:#c83c3c; --warning:#9b660d; --muted:#5c6775; --line:#dde3ea; }
      * { margin:0; padding:0; box-sizing:border-box; }
      html, body { width:#{@width}px; height:#{@height}px; }
      body { font-family: ui-rounded,"SF Pro Rounded",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
        background: linear-gradient(135deg,#eef1f4 0%,#e6ecf3 55%,#eef1f6 100%); color:var(--content);
        display:flex; padding:44px; }
      .card { flex:1; background:var(--base-200); border:1px solid var(--line); border-radius:28px;
        box-shadow:0 18px 50px rgba(16,24,32,0.14); padding:44px 52px; display:flex; flex-direction:column; }
      .card > * { flex-shrink:0; }
      .top { display:flex; align-items:center; justify-content:space-between; }
      .brand { display:flex; align-items:center; gap:12px; }
      .brand img { width:40px; height:40px; border-radius:999px; }
      .brand span { font-size:26px; font-weight:750; letter-spacing:-0.02em; }
      .brand span b { color:var(--primary); }
      .tag { font-size:20px; font-weight:700; color:var(--primary); background:rgba(47,107,171,0.10);
        padding:8px 18px; border-radius:999px; }
      .quiz { margin-top:18px; font-size:30px; font-weight:700; letter-spacing:-0.02em; color:var(--primary);
        line-height:1.45; padding-bottom:2px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .hero { margin-top:30px; display:flex; align-items:center; justify-content:space-between; gap:32px; }
      .score { font-size:74px; font-weight:800; color:var(--primary); letter-spacing:-0.03em; line-height:1; white-space:nowrap; }
      .score small { font-size:38px; color:var(--muted); font-weight:700; }
      .hero-meta { display:flex; flex-direction:column; gap:4px; }
      .hero-meta .pct { font-size:25px; font-weight:700; }
      .hero-meta .time { font-size:21px; color:var(--muted); }
      .stats { margin-top:26px; display:grid; grid-template-columns:1fr 1fr; column-gap:56px; row-gap:14px;
        border-top:1px solid var(--line); padding-top:24px; }
      .row { display:flex; align-items:baseline; justify-content:space-between; gap:16px; }
      .row .lbl { font-size:23px; color:var(--muted); }
      .row .val { font-size:25px; font-weight:750; font-variant-numeric:tabular-nums; }
      .val.ok { color:var(--success); } .val.err { color:var(--error); } .val.warn { color:var(--warning); }
    </style></head><body>
      <div class="card">
        <div class="top">
          <div class="brand"><img src="#{logo_data_uri()}" alt="" /><span>Quiz<b>zes</b></span></div>
          <div class="tag">Resultado</div>
        </div>
        <div class="quiz">#{esc(name)}</div>
        <div class="hero">
          <div class="hero-meta">
            <div class="pct">#{esc(dec(attempt.percent))}% de aproveitamento</div>
            #{if duration, do: ~s(<div class="time">tempo utilizado: #{esc(duration)}</div>), else: ""}
          </div>
          <div class="score">#{esc(dec(attempt.score))}<small>/#{esc(dec(attempt.max_score))}</small></div>
        </div>
        <div class="stats">
    #{rows_html}
        </div>
      </div>
    </body></html>
    """
  end

  defp logo_data_uri do
    png = File.read!(Application.app_dir(:quiz_project, "priv/static/images/logo.png"))
    "data:image/png;base64," <> Base.encode64(png)
  end

  defp truncate(str, max) do
    if String.length(str) > max, do: String.slice(str, 0, max) <> "…", else: str
  end

  defp dec(nil), do: "0"
  defp dec(d), do: d |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp esc(value), do: value |> to_string() |> Plug.HTML.html_escape()
end
