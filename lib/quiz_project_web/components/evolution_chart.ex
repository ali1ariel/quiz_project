defmodule QuizProjectWeb.EvolutionChart do
  @moduledoc """
  Linha evolutiva das notas (%) das tentativas finalizadas de UMA versão de
  quiz, em ordem cronológica. Versões não se misturam: cada versão é avaliada
  como um quiz próprio, então cada gráfico recebe apenas tentativas da mesma
  versão.

  Única série: sem legenda; rótulo direto no último ponto e detalhe por ponto
  no hover/foco. A lista de tentativas ao lado do gráfico carrega todos os
  valores, então o hover complementa sem esconder nada.
  """
  use Phoenix.Component

  attr :chart, :map, required: true
  attr :id, :string, required: true

  def evolution_chart(assigns) do
    ~H"""
    <figure id={@id} class="w-full">
      <svg
        viewBox={"0 0 #{@chart.w} #{@chart.h}"}
        class="w-full h-auto"
        role="img"
        aria-label={@chart.aria}
      >
        <g :for={tick <- @chart.ticks}>
          <line
            x1={@chart.pad_l}
            x2={@chart.w - @chart.pad_r}
            y1={tick.y}
            y2={tick.y}
            stroke="color-mix(in oklab, var(--color-base-content) 14%, transparent)"
            stroke-width="1"
          />
          <text
            x={@chart.pad_l - 6}
            y={tick.y + 3}
            text-anchor="end"
            font-size="10"
            fill="var(--color-base-content)"
            opacity="0.55"
          >
            {tick.label}
          </text>
        </g>

        <path
          d={@chart.path}
          fill="none"
          stroke="var(--color-primary)"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />

        <g :for={pt <- @chart.points} class="group/pt cursor-default" tabindex="0">
          <title>{pt.tooltip}</title>
          <circle cx={pt.x} cy={pt.y} r="14" fill="transparent" />
          <circle
            cx={pt.x}
            cy={pt.y}
            r="4"
            fill="var(--color-primary)"
            stroke="var(--color-base-200)"
            stroke-width="2"
          />
          <text
            x={pt.tx}
            y={pt.ty}
            text-anchor="middle"
            font-size="10"
            font-weight="600"
            fill="var(--color-base-content)"
            stroke="var(--color-base-200)"
            stroke-width="3"
            paint-order="stroke"
            class="opacity-0 group-hover/pt:opacity-100 group-focus-within/pt:opacity-100 transition-opacity pointer-events-none"
          >
            {pt.tooltip}
          </text>
        </g>

        <text
          x={@chart.end_label.x}
          y={@chart.end_label.y}
          text-anchor="start"
          font-size="11"
          font-weight="600"
          fill="var(--color-base-content)"
        >
          {@chart.end_label.text}
        </text>
      </svg>
    </figure>
    """
  end

  @doc """
  Geometria do gráfico calculada no servidor a partir das tentativas
  finalizadas de uma única versão, já em ordem cronológica. Eixo y fixo em
  0–100% e tentativas com espaçamento uniforme no x. Só existe linha com
  2+ notas — com menos, retorna `nil` e o chamador omite o gráfico.
  """
  def chart_data(finished, opts \\ [])

  def chart_data(finished, _opts) when length(finished) < 2, do: nil

  def chart_data(finished, opts) do
    w = Keyword.get(opts, :w, 560)
    h = Keyword.get(opts, :h, 150)
    {pad_l, pad_r, pad_t, pad_b} = {34, 52, 18, 10}
    span_x = w - pad_l - pad_r
    span_y = h - pad_t - pad_b
    n = length(finished)

    points =
      finished
      |> Enum.with_index()
      |> Enum.map(fn {attempt, i} ->
        percent = attempt.percent |> Decimal.to_float() |> min(100.0) |> max(0.0)
        x = Float.round(pad_l + i * span_x / (n - 1), 1)
        y = Float.round(pad_t + (100 - percent) / 100 * span_y, 1)

        %{
          x: x,
          y: y,
          tooltip:
            "#{format_decimal(attempt.score)}/#{format_decimal(attempt.max_score)} " <>
              "(#{format_decimal(attempt.percent)}%) · " <>
              Calendar.strftime(attempt.finished_at, "%d/%m"),
          # rótulo do hover: acima do ponto, ou abaixo quando cola no topo,
          # com x preso ao miolo para o texto não vazar do viewBox
          tx: x |> min(w - 80.0) |> max(80.0),
          ty: if(y < 32, do: y + 24, else: y - 12)
        }
      end)

    last = List.last(points)

    %{
      w: w,
      h: h,
      pad_l: pad_l,
      pad_r: pad_r,
      path: "M" <> Enum.map_join(points, " L", &"#{&1.x},#{&1.y}"),
      points: points,
      ticks:
        Enum.map([0, 50, 100], fn value ->
          %{label: "#{value}", y: Float.round(pad_t + (100 - value) / 100 * span_y, 1)}
        end),
      end_label: %{
        x: last.x + 10,
        y: last.y + 4,
        text: Enum.at(finished, -1).percent |> format_decimal() |> Kernel.<>("%")
      },
      aria:
        "Evolução das notas: " <>
          Enum.map_join(finished, ", ", &"#{format_decimal(&1.percent)}%")
    }
  end

  defp format_decimal(nil), do: "0"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end
end
