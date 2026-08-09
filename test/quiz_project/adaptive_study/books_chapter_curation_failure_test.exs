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
    def curate_mindmap(_text), do: {:error, :boom}
  end

  defmodule CrashingAI do
    @moduledoc false
    @behaviour QuizProject.AI.Provider

    def generate_tags(_statement), do: {:error, :not_implemented}
    def grade_text_answer(_statement, _reference, _answer), do: {:error, :not_implemented}
    def generate_reference(_statement), do: {:error, :not_implemented}
    def evaluate_progression(_summary), do: {:error, :not_implemented}
    def curate_mindmap(_text), do: raise("boom inesperado")
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
end
