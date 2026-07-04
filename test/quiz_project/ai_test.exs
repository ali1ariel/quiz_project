defmodule QuizProject.AITest do
  use ExUnit.Case, async: true

  alias QuizProject.AI.Fake

  describe "provider Fake" do
    test "gera no máximo 4 tags sem stopwords" do
      {:ok, tags} =
        Fake.generate_tags("A fotossíntese converte a luz do sol em energia química nas plantas")

      assert length(tags) <= 4
      assert tags != []
      refute "de" in tags
      refute "em" in tags
    end

    test "resposta idêntica à referência pontua alto" do
      reference = "A fotossíntese converte luz solar em energia química"
      {:ok, %{percent: percent, feedback: feedback}} =
        Fake.grade_text_answer("Explique a fotossíntese", reference, reference)

      assert percent == 100
      assert feedback =~ "principais pontos"
    end

    test "resposta vazia pontua zero" do
      {:ok, %{percent: 0}} =
        Fake.grade_text_answer("Explique", "Uma referência qualquer", "")
    end

    test "gera referência a partir do enunciado" do
      {:ok, reference} = Fake.generate_reference("O que é polimorfismo?")
      assert reference =~ "polimorfismo"
    end
  end

  describe "fachada" do
    test "usa o provider configurado e limita tags a 4" do
      {:ok, tags} =
        QuizProject.AI.generate_tags(
          "história geografia matemática física química biologia astronomia"
        )

      assert length(tags) <= 4
    end

    test "limita percent entre 0 e 100" do
      {:ok, %{percent: percent}} =
        QuizProject.AI.grade_text_answer("Enunciado", "referência exata", "referência exata")

      assert percent >= 0 and percent <= 100
    end
  end
end
