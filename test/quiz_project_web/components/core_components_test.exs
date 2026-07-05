defmodule QuizProjectWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import QuizProjectWeb.CoreComponents, only: [format_duration: 2]

  describe "format_duration/2" do
    @base ~U[2026-07-04 12:00:00Z]

    test "abaixo de um minuto mostra apenas segundos" do
      assert format_duration(@base, DateTime.add(@base, 42)) == "42s"
      assert format_duration(@base, @base) == "0s"
    end

    test "abaixo de uma hora mostra minutos e segundos com padding" do
      assert format_duration(@base, DateTime.add(@base, 4 * 60 + 7)) == "4min 07s"
      assert format_duration(@base, DateTime.add(@base, 59 * 60 + 59)) == "59min 59s"
    end

    test "a partir de uma hora omite segundos" do
      assert format_duration(@base, DateTime.add(@base, 3600 + 4 * 60 + 30)) == "1h 04min"
    end

    test "intervalo negativo trunca em zero" do
      assert format_duration(@base, DateTime.add(@base, -5)) == "0s"
    end

    test "instantes ausentes retornam nil" do
      assert format_duration(nil, @base) == nil
      assert format_duration(@base, nil) == nil
    end
  end
end
