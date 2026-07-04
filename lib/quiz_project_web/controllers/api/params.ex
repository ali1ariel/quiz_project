defmodule QuizProjectWeb.Api.Params do
  @moduledoc false

  @quiz_fields %{
    "name" => :name,
    "description" => :description,
    "total_points" => :total_points,
    "unequal_weights" => :unequal_weights,
    "question_order_mode" => :question_order_mode
  }

  @question_fields %{
    "statement" => :statement,
    "type" => :type,
    "allow_partial_credit" => :allow_partial_credit,
    "true_false_answer" => :true_false_answer,
    "editor_note" => :editor_note,
    "weight" => :weight,
    "position" => :position
  }

  @option_fields %{
    "id" => :id,
    "text" => :text,
    "correct" => :correct,
    "position" => :position
  }

  @order_modes %{"fixed" => :fixed, "random" => :random, "ai" => :ai}
  @question_types %{
    "true_false" => :true_false,
    "single" => :single,
    "multiple" => :multiple,
    "text" => :text
  }

  def quiz(params) when is_map(params) do
    params
    |> take_known(@quiz_fields)
    |> map_known_value(:question_order_mode, @order_modes)
  end

  def question(params) when is_map(params) do
    params
    |> take_known(@question_fields)
    |> map_known_value(:type, @question_types)
  end

  def options(%{"options" => options}) when is_list(options) do
    {:ok, Enum.map(options, &take_known(&1, @option_fields))}
  end

  def options(%{"options" => _}), do: {:error, "options precisa ser uma lista"}
  def options(_params), do: {:ok, nil}

  defp take_known(params, fields) do
    Enum.reduce(fields, %{}, fn {external, internal}, attrs ->
      if Map.has_key?(params, external) do
        Map.put(attrs, internal, Map.get(params, external))
      else
        attrs
      end
    end)
  end

  defp map_known_value(attrs, key, values) do
    case attrs do
      %{^key => value} -> Map.put(attrs, key, Map.get(values, value, value))
      _ -> attrs
    end
  end
end
