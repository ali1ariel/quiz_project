defmodule QuizProject.AdaptiveStudy.Books do
  @moduledoc """
  Ingestão e consulta de livros: grava o que o `QuizProject.Epub` extraiu e
  responde as perguntas que o leitor, a busca e o filtro fazem.

  Os blocos são a única cópia do texto. Quem quer texto corrido chama
  `material_text/1` ou `chapter_text/1`, que concatenam na ordem — reconstruir
  é estrutural, não uma aproximação a verificar.
  """

  require Ash.Query
  require Logger

  alias QuizProject.AdaptiveStudy.Block
  alias QuizProject.AdaptiveStudy.Chapter
  alias QuizProject.AdaptiveStudy.NodeBlock
  alias QuizProject.AdaptiveStudy.ReadingPosition
  alias QuizProject.AdaptiveStudy.ReadingPreference
  alias QuizProject.Epub

  @separator "\n\n"

  # Ingestão

  @doc """
  Processa o `.epub` fora do processo que atende o usuário.

  4.714 blocos não entram dentro do request do upload. O caminho é o mesmo que a
  geração do mapa mental já usa: `Jobs.run/1` e aviso por PubSub ao terminar —
  aqui com progresso por capítulo, porque um livro leva alguns segundos.
  """
  def ingest_async(material, binary, user) do
    Logger.info("[Books] Iniciando ingestão do EPUB (Material #{material.id})...")

    QuizProject.Jobs.run(fn -> ingest(material, binary, user) end)
  end

  @doc """
  Ingere o livro inteiro: capítulos, blocos e a folha de estilo filtrada.

  Devolve `{:ok, material}` com o material já atualizado, ou `{:error, motivo}`
  com o motivo gravado em `ingest_error` para a tela poder explicá-lo.
  """
  def ingest(material, binary, user) do
    case Epub.parse(binary, on_chapter: &broadcast_progress(material, &1)) do
      {:ok, book} ->
        persist(material, book, user)

      {:error, reason} ->
        Logger.error("[Books] Falha ao ingerir o Material #{material.id}: #{inspect(reason)}")

        QuizProject.AdaptiveStudy.update_material(
          material,
          %{status: "failed", ingest_error: Epub.error_message(reason)},
          user
        )

        broadcast_finished(material, user, {:error, reason})
        {:error, reason}
    end
  end

  defp persist(material, book, user) do
    # Reingerir substitui o livro inteiro. Os `source_id` da editora são
    # estáveis, então a demarcação da IA volta a cair no lugar certo — mas os
    # uuid dos blocos mudam, e `node_blocks` cai junto por chave estrangeira.
    delete_chapters(material)

    Enum.each(book.chapters, fn chapter ->
      {:ok, row} =
        Chapter
        |> Ash.Changeset.for_create(
          :create,
          %{
            material_id: material.id,
            source_id: chapter.source_id,
            href: chapter.href,
            title: chapter.title,
            position: chapter.position,
            level: chapter.level,
            kind: chapter.kind,
            block_count: length(chapter.blocks)
          },
          authorize?: false
        )
        |> Ash.create()

      insert_blocks(material, row, chapter.blocks)
    end)

    result =
      QuizProject.AdaptiveStudy.update_material(
        material,
        %{
          title: title_for(material, book),
          author: book.author,
          format: :epub,
          reader_css: book.css,
          status: "draft",
          ingest_error: nil
        },
        user
      )

    case result do
      {:ok, updated} ->
        Logger.info(
          "[Books] Livro \"#{updated.title}\" ingerido: #{length(book.chapters)} capítulos, #{Epub.Book.block_count(book)} blocos."
        )

        broadcast_finished(updated, user, :ok)
        {:ok, updated}

      error ->
        error
    end
  end

  defp insert_blocks(material, chapter, blocks) do
    blocks
    |> Enum.map(fn block ->
      %{
        material_id: material.id,
        chapter_id: chapter.id,
        source_id: block.source_id,
        position: block.position,
        type: block.type,
        lang: block.lang,
        caption: block.caption,
        content: block.content,
        annotations: block.annotations
      }
    end)
    |> Ash.bulk_create!(Block, :create,
      authorize?: false,
      return_records?: false,
      return_errors?: true,
      stop_on_error?: true,
      batch_size: 500
    )
  end

  # O título que o usuário escreveu no upload manda sobre o do OPF; só o
  # provisório dá lugar ao do livro.
  defp title_for(material, book) do
    if material.title in ["", "Processando material...", "Processando livro..."],
      do: book.title,
      else: material.title
  end

  defp delete_chapters(material) do
    Chapter
    |> Ash.Query.filter(material_id == ^material.id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, strategy: [:stream])
  end

  @doc "Tópico do PubSub com o andamento da ingestão de um material."
  def ingest_topic(material_id), do: "material:#{material_id}:ingest"

  defp broadcast_progress(material, {index, total, title}) do
    Phoenix.PubSub.broadcast(
      QuizProject.PubSub,
      ingest_topic(material.id),
      {:ingest_progress, %{material_id: material.id, done: index, total: total, title: title}}
    )
  end

  # A conclusão vai também para o tópico do usuário, que é onde a lista de
  # materiais e o sino de notificações já escutam.
  defp broadcast_finished(material, user, result) do
    Phoenix.PubSub.broadcast(
      QuizProject.PubSub,
      ingest_topic(material.id),
      {:ingest_finished, %{material_id: material.id, result: result}}
    )

    Phoenix.PubSub.broadcast(
      QuizProject.PubSub,
      "user:#{user.id}:attempts",
      {:ingest_finished, %{material_id: material.id, result: result}}
    )
  end

  # Leitura

  @doc "Capítulos do livro em ordem de leitura."
  def list_chapters(material_id) do
    Chapter
    |> Ash.Query.filter(material_id == ^material_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Capítulo por posição no livro, com os blocos já carregados.

  A posição vem da URL para que o lugar da leitura seja compartilhável e o botão
  voltar do navegador funcione dentro do livro.
  """
  def get_chapter(material_id, position) when is_integer(position) do
    Chapter
    |> Ash.Query.filter(material_id == ^material_id and position == ^position)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, chapter} -> {:ok, chapter}
      error -> error
    end
  end

  @doc "Primeiro capítulo de conteúdo, pulando o pré-textual."
  def first_body_chapter(material_id) do
    chapters = list_chapters(material_id)

    Enum.find(chapters, List.first(chapters), &(&1.kind == :body))
  end

  @doc "Blocos de um capítulo, na ordem em que devem ser renderizados."
  def list_blocks(chapter_id) do
    Block
    |> Ash.Query.filter(chapter_id == ^chapter_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Total de blocos do livro."
  def block_count(material_id) do
    Block
    |> Ash.Query.filter(material_id == ^material_id)
    |> Ash.count!(authorize?: false)
  end

  # Reconstrução

  @doc """
  Texto corrido do livro.

  É concatenação sob demanda, e não uma coluna: guardar o texto de novo seria
  uma segunda cópia de 1,2MB por livro que ninguém lê.
  """
  def material_text(material_id, opts \\ []) do
    query =
      Block
      |> Ash.Query.filter(material_id == ^material_id)
      |> Ash.Query.sort(position: :asc)

    query =
      if Keyword.get(opts, :body_only, false) do
        chapter_ids =
          material_id
          |> list_chapters()
          |> Enum.filter(&(&1.kind == :body))
          |> Enum.map(& &1.id)

        Ash.Query.filter(query, chapter_id in ^chapter_ids)
      else
        query
      end

    query
    |> Ash.read!(authorize?: false)
    |> join_blocks()
  end

  @doc "Texto corrido de um capítulo."
  def chapter_text(chapter_id), do: chapter_id |> list_blocks() |> join_blocks()

  defp join_blocks(blocks), do: Enum.map_join(blocks, @separator, & &1.content)

  # Busca

  @doc """
  Busca dentro do livro. O resultado aponta para o bloco, que é a mesma âncora
  da posição e do filtro — cai de graça no modelo.
  """
  def search(material_id, term, opts \\ []) do
    term = String.trim(term)
    limit = Keyword.get(opts, :limit, 50)

    if String.length(term) < 2 do
      []
    else
      Block
      |> Ash.Query.filter(material_id == ^material_id)
      |> Ash.Query.filter(
        fragment(
          "to_tsvector('simple', ?) @@ plainto_tsquery('simple', ?)",
          content,
          ^term
        )
      )
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.limit(limit)
      |> Ash.read!(authorize?: false)
    end
  end

  # Demarcação e filtro

  @doc """
  Grava a cobertura de um nó do mapa mental sobre um intervalo de blocos.

  `positions` são posições absolutas no livro, que é o que a IA devolve ao
  processar um capítulo. A demarcação anterior daquele nó é substituída.
  """
  def demarcate(material_id, node_id, positions, opts \\ []) when is_list(positions) do
    confidence = Keyword.get(opts, :confidence, Decimal.new("1.0"))

    NodeBlock
    |> Ash.Query.filter(material_id == ^material_id and node_id == ^node_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, strategy: [:stream])

    blocks =
      Block
      |> Ash.Query.filter(material_id == ^material_id and position in ^positions)
      |> Ash.read!(authorize?: false)

    blocks
    |> Enum.map(
      &%{
        material_id: material_id,
        node_id: node_id,
        block_id: &1.id,
        confidence: confidence
      }
    )
    |> Ash.bulk_create!(NodeBlock, :create,
      authorize?: false,
      return_records?: false,
      return_errors?: true,
      stop_on_error?: true
    )

    length(blocks)
  end

  @doc """
  Dado um capítulo, o mapa `block_id => [node_id]` de quem cobre cada bloco.

  É a consulta que o filtro do leitor faz a cada render, e é por isso que
  `node_blocks` é tabela de junção indexada por `block_id`: nenhuma forma do
  filtro pode depender de varrer o texto em tempo de render.
  """
  def coverage(chapter_id) do
    block_ids = chapter_id |> list_blocks() |> Enum.map(& &1.id)

    NodeBlock
    |> Ash.Query.filter(block_id in ^block_ids)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.block_id, & &1.node_id)
  end

  @doc "Blocos que um nó cobre, na ordem do livro."
  def blocks_for_node(material_id, node_id) do
    ids =
      NodeBlock
      |> Ash.Query.filter(material_id == ^material_id and node_id == ^node_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.block_id)

    Block
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  # Posição e aparência

  @doc """
  Andamento de vários livros de uma vez: `%{material_id => %{total:, current:}}`.

  Duas consultas para a biblioteca inteira, em vez de duas por cartão. `current`
  é `nil` enquanto o livro não foi aberto.
  """
  def library_progress(user_id, material_ids) do
    chapters =
      Chapter
      |> Ash.Query.filter(material_id in ^material_ids)
      |> Ash.read!(authorize?: false)

    totals = Enum.frequencies_by(chapters, & &1.material_id)
    numbers = Map.new(chapters, &{&1.id, &1.position})

    positions =
      ReadingPosition
      |> Ash.Query.filter(user_id == ^user_id and material_id in ^material_ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.material_id, Map.get(numbers, &1.chapter_id)})

    Map.new(material_ids, fn id ->
      {id, %{total: Map.get(totals, id, 0), current: Map.get(positions, id)}}
    end)
  end

  @doc "Onde o usuário parou neste livro, ou `nil` se ainda não abriu."
  def get_position(user_id, material_id) do
    ReadingPosition
    |> Ash.Query.filter(user_id == ^user_id and material_id == ^material_id)
    |> Ash.read_one!(authorize?: false)
  end

  @doc "Salva a posição de leitura, sobrescrevendo a anterior do mesmo livro."
  def save_position(user_id, material_id, attrs) do
    ReadingPosition
    |> Ash.Changeset.for_create(
      :upsert,
      Map.merge(attrs, %{user_id: user_id, material_id: material_id}),
      authorize?: false
    )
    |> Ash.create()
  end

  @doc "Aparência escolhida pelo usuário, com os padrões quando ainda não há linha."
  def get_preferences(user_id) do
    ReadingPreference
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        %ReadingPreference{
          user_id: user_id,
          font: :serif,
          font_size: 100,
          line_height: 175,
          width: :medium
        }

      preference ->
        preference
    end
  end

  @doc "Salva a aparência do leitor para o usuário."
  def save_preferences(user_id, attrs) do
    ReadingPreference
    |> Ash.Changeset.for_create(:upsert, Map.put(attrs, :user_id, user_id), authorize?: false)
    |> Ash.create()
  end
end
