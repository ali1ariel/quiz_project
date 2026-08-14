defmodule QuizProject.AdaptiveStudy.BooksChapterCurationFailureTest do
  @moduledoc """
  Módulo à parte, sem `async`, porque os testes trocam a configuração global
  `:quiz_project, :ai_provider` para simular falha na curadoria. Rodar isso em
  paralelo com outro teste que também dispara IA (comum no resto da suíte, que
  é `async: true`) contaminaria aquele teste com o provider errado.
  """
  use QuizProject.DataCase, async: false

  alias QuizProject.Accounts
  alias QuizProject.AdaptiveStudy
  alias QuizProject.AdaptiveStudy.Books
  alias QuizProject.EpubFixture

  defmodule FailingAI do
    @moduledoc false
    @behaviour QuizProject.AI.Provider

    def generate_tags(_statement), do: {:error, :not_implemented}
    def grade_text_answer(_statement, _reference, _answer), do: {:error, :not_implemented}
    def generate_reference(_statement), do: {:error, :not_implemented}
    def evaluate_progression(_summary), do: {:error, :not_implemented}
    def curate_mindmap(_text, _opts \\ []), do: {:error, :boom}
  end

  defmodule MeteredAI do
    @moduledoc false
    @behaviour QuizProject.AI.Provider

    # O uso que um provedor real informaria: saída bem maior que a entrada,
    # porque JSON estruturado e tokens de raciocínio entram nela.
    @usage %{input: 8_000, output: 24_000}

    def usage, do: @usage

    def generate_tags(_statement), do: {:error, :not_implemented}
    def grade_text_answer(_statement, _reference, _answer), do: {:error, :not_implemented}
    def generate_reference(_statement), do: {:error, :not_implemented}
    def evaluate_progression(_summary), do: {:error, :not_implemented}

    def curate_mindmap(text, _opts \\ []) do
      {:ok, resultado, nil} = QuizProject.AI.Fake.curate_mindmap(text)
      {:ok, resultado, @usage}
    end
  end

  defmodule CrashingAI do
    @moduledoc false
    @behaviour QuizProject.AI.Provider

    def generate_tags(_statement), do: {:error, :not_implemented}
    def grade_text_answer(_statement, _reference, _answer), do: {:error, :not_implemented}
    def generate_reference(_statement), do: {:error, :not_implemented}
    def evaluate_progression(_summary), do: {:error, :not_implemented}
    def curate_mindmap(_text, _opts \\ []), do: raise("boom inesperado")
  end

  setup do
    original_provider = Application.get_env(:quiz_project, :ai_provider)
    on_exit(fn -> Application.put_env(:quiz_project, :ai_provider, original_provider) end)

    {:ok, user} =
      Accounts.register_user(%{
        email: "leitor#{System.unique_integer([:positive])}@teste.com",
        name: "Leitor Teste",
        password: "Password123!"
      })

    {:ok, material} =
      AdaptiveStudy.create_material(user, %{
        title: "Processando livro...",
        format: :epub,
        status: "ingesting"
      })

    {:ok, material} = Books.ingest(material, EpubFixture.build(), user)
    {:ok, chapter} = Books.get_chapter(material.id, 2)

    %{user: user, chapter: chapter}
  end

  test "IA que devolve erro marca o capítulo como falho e não deixa material órfão", %{
    chapter: chapter,
    user: user
  } do
    Application.put_env(:quiz_project, :ai_provider, FailingAI)

    assert {:ok, _processing} = Books.curate_chapter_async(chapter, user)

    finished = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))
    assert finished.curation_status == :failed
    assert finished.curated_material_id == nil
    assert Books.chapter_ai_state(finished) == :failed

    assert AdaptiveStudy.list_materials(user) |> Enum.count(&(&1.format == :text)) == 0

    # o :failed libera nova tentativa, ao contrário de um :processing travado
    assert {:ok, retry} = Books.curate_chapter_async(finished, user)
    assert retry.curation_status == :processing
  end

  test "exceção inesperada também cai em :failed, nunca trava em :processing", %{
    chapter: chapter,
    user: user
  } do
    Application.put_env(:quiz_project, :ai_provider, CrashingAI)

    assert {:ok, _processing} = Books.curate_chapter_async(chapter, user)

    finished = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))
    assert finished.curation_status == :failed
    assert finished.curated_material_id == nil

    assert AdaptiveStudy.list_materials(user) |> Enum.count(&(&1.format == :text)) == 0
  end

  describe "uso real de tokens" do
    test "grava no capítulo o que o provedor informou", %{user: user, chapter: chapter} do
      Application.put_env(:quiz_project, :ai_provider, MeteredAI)

      {:ok, _} = Books.curate_chapter_async(chapter, user, model: "claude-opus-5")

      curado = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert curado.curation_status == :done
      assert curado.usage_input_tokens == MeteredAI.usage().input
      assert curado.usage_output_tokens == MeteredAI.usage().output
      assert curado.curated_model == "claude-opus-5"
    end

    # É o ponto da mudança inteira: a previsão para de depender de uma constante
    # calibrada à mão e passa a sair do que já foi cobrado.
    test "a previsão passa a usar a razão medida", %{user: user, chapter: chapter} do
      assert %{basis: :assumed} = Books.curation_forecast(10_000)

      Application.put_env(:quiz_project, :ai_provider, MeteredAI)
      {:ok, _} = Books.curate_chapter_async(chapter, user, model: "claude-opus-5")

      curado = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert {razao, 1} = Books.measured_output_ratio()
      assert_in_delta razao, MeteredAI.usage().output / curado.estimated_tokens, 0.001

      assert %{basis: {:measured, 1}, output: saida} = Books.curation_forecast(10_000)
      assert saida == round(10_000 * razao)
    end

    # Curadoria que falhou não tem uso medido, e nulo diz isso melhor que zero:
    # zero entraria na média e a puxaria para baixo sem ter havido medição.
    test "falha não grava uso nenhum", %{user: user, chapter: chapter} do
      Application.put_env(:quiz_project, :ai_provider, FailingAI)

      {:ok, _} = Books.curate_chapter_async(chapter, user)

      falho = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert falho.curation_status == :failed
      assert is_nil(falho.usage_input_tokens)
      assert is_nil(falho.usage_output_tokens)
      assert Books.measured_output_ratio() == nil
    end

    # O Fake não consome token de ninguém; gravar zero afirmaria uma medição
    # que não houve e contaminaria a razão medida.
    test "provedor local não inventa medição", %{user: user, chapter: chapter} do
      {:ok, _} = Books.curate_chapter_async(chapter, user)

      curado = Enum.find(Books.list_chapters(chapter.material_id), &(&1.id == chapter.id))

      assert curado.curation_status == :done
      assert is_nil(curado.usage_output_tokens)
      assert Books.measured_output_ratio() == nil
    end
  end
end
