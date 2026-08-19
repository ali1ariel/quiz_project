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
  alias QuizProject.AdaptiveStudy.Highlight
  alias QuizProject.AdaptiveStudy.ImageStore
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
    ImageStore.put_all(material.id, book.images)

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
            block_count: length(chapter.blocks),
            estimated_tokens: estimate_tokens(chapter.blocks)
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
          image_flags: invertible_paths(book.images),
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
        image_path: block.image_path,
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

  # Só as invertíveis entram no mapa: as opacas são a maioria em livro de
  # capturas de tela, e guardar `false` para cada uma seria peso sem uso.
  defp invertible_paths(images) do
    for {path, %{invertible: true}} <- images, into: %{}, do: {path, true}
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

  # Estimativa de tokens

  # Pesos em caracteres por token. Código tokeniza pior que prosa — identificador
  # quebrado em pedaços, indentação, pontuação — e nos dois livros medidos ele é
  # ~20% do corpo, o que puxa a conta para cima justamente nos capítulos densos.
  #
  # São aproximações de tokenizador BPE, não medição. `priv/docs` traz o script
  # de calibração contra a contagem real da Anthropic, que é exata e gratuita.
  @chars_per_token %{code: 2.8, table: 3.0}
  @chars_per_token_default 4.0

  # Acima disto a curadoria arrisca truncar. A conta agora tem base: a saída sai
  # ~2,5x a entrada (ver `@curation_output_ratio`) e divide com o raciocínio um
  # teto de 64.000 tokens no provedor Claude, então o ponto de estouro fica perto
  # de 25.600 tokens de entrada. 20.000 deixa ~20% de folga.
  #
  # Confere com o único caso observado: um capítulo de 21.709 tokens estimados
  # passou do limiar, disparou o aviso e ainda assim concluiu.
  @safe_curation_tokens 20_000

  @doc """
  Tokens estimados para um conjunto de blocos, ponderados por tipo.

  Serve para avisar o tamanho antes de mandar o capítulo para a IA, não para
  cobrança: é estimativa, e está marcada como tal em toda a interface.
  """
  def estimate_tokens(blocks) do
    blocks
    |> Enum.reduce(0.0, fn block, total ->
      ratio = Map.get(@chars_per_token, block.type, @chars_per_token_default)
      total + String.length(block.content) / ratio
    end)
    |> round()
  end

  @doc """
  Recalcula a estimativa dos capítulos já gravados.

  A estimativa passou a ser gravada na ingestão depois que os primeiros livros
  já estavam no banco, e coluna nova em linha antiga vale zero. Reingerir
  resolveria, mas custa um upload por livro; isto resolve sem tocar no texto.
  """
  def backfill_estimated_tokens do
    Chapter
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn chapter, atualizados ->
      estimado = chapter.id |> list_blocks() |> estimate_tokens()

      if estimado == chapter.estimated_tokens do
        atualizados
      else
        chapter
        |> Ash.Changeset.for_update(:update, %{estimated_tokens: estimado}, authorize?: false)
        |> Ash.update!()

        atualizados + 1
      end
    end)
  end

  # Quanto a resposta cresce em relação à entrada. Já foi 1.0 — "a resposta
  # devolve o texto inteiro, logo é do tamanho dele" — e isso subestimou o custo
  # real em 2,3x na primeira medição contra fatura.
  #
  # Três coisas somam além do texto devolvido, e nenhuma estava na conta:
  # a estrutura JSON (ids de nó, hierarquia, referências cruzadas); o raciocínio,
  # que no Claude roda com `effort: "high"` e é cobrado como saída; e o fato de
  # a razão de caracteres por token subestimar nos modelos recentes.
  #
  # Medição única: capítulo de 81.332 caracteres (21.709 tokens estimados) curado
  # com claude-opus-5 custou US$ 1,47, o que implica ~54.500 tokens de saída.
  # Como o número absorve também o erro do lado da entrada, refazer a conta é
  # obrigatório se `@chars_per_token` mudar — ver `priv/docs/modelos_de_ia.md`.
  @curation_output_ratio 2.5

  @doc """
  Tokens de entrada e de saída previstos para curar um capítulo deste tamanho.

  Usa a razão medida das curadorias já feitas quando existe alguma, e só cai em
  `@curation_output_ratio` enquanto não há medição nenhuma. A previsão melhora
  sozinha a cada capítulo processado, em vez de depender de alguém lembrar de
  recalibrar a constante.
  """
  def curation_forecast(estimated_tokens) do
    {razao, base} =
      case measured_output_ratio() do
        nil -> {@curation_output_ratio, :assumed}
        {razao, amostras} -> {razao, {:measured, amostras}}
      end

    %{input: estimated_tokens, output: round(estimated_tokens * razao), basis: base}
  end

  @doc """
  Razão saída/entrada medida nas curadorias concluídas e quantas entraram na
  conta, ou `nil` se ainda não há medição nenhuma.

  Compara o uso real informado pelo provedor com a **estimativa** de entrada, e
  não com o uso real de entrada, de propósito: a previsão parte da estimativa, e
  é o erro dela ponta a ponta que precisa ser corrigido. Corrigir só o lado da
  saída deixaria o erro do tokenizador de fora da conta.
  """
  def measured_output_ratio do
    medidos =
      Chapter
      |> Ash.Query.filter(not is_nil(usage_output_tokens) and estimated_tokens > 0)
      |> Ash.read!(authorize?: false)

    case medidos do
      [] ->
        nil

      capitulos ->
        saida = capitulos |> Enum.map(& &1.usage_output_tokens) |> Enum.sum()
        estimada = capitulos |> Enum.map(& &1.estimated_tokens) |> Enum.sum()

        # Agregado, e não média das razões: um capítulo minúsculo com razão
        # esquisita não pode pesar igual a um capítulo de 20k tokens.
        {saida / estimada, length(capitulos)}
    end
  end

  @doc "Indica se o capítulo é grande a ponto de a resposta da IA truncar."
  def curation_risky?(estimated_tokens), do: estimated_tokens > @safe_curation_tokens

  @doc "Limiar acima do qual a curadoria é sinalizada como arriscada."
  def safe_curation_tokens, do: @safe_curation_tokens

  # Curadoria de capítulo por IA

  @doc """
  Envia o capítulo para curadoria de IA: cria um novo Material de Estudo (texto)
  a partir do seu conteúdo e roda o mesmo pipeline de decomposição em Mapa
  Mental do upload manual, em background.

  A transição para `:processing` é um único `UPDATE...WHERE` com o status atual
  no filtro (`start_chapter_curation/1`), então cliques repetidos no botão da
  barra de leitura — mesmo simultâneos — nunca disparam dois processamentos do
  mesmo capítulo: só o primeiro encontra a linha no estado esperado.

  Devolve `{:ok, capítulo}` com o capítulo já em `:processing`, ou
  `{:error, :already_processing}` quando o capítulo já está em processamento ou
  já foi curado.
  """
  def curate_chapter_async(chapter, user, opts \\ []) do
    case start_chapter_curation(chapter) do
      {:ok, chapter} ->
        Logger.info("[Books] Iniciando curadoria de IA do capítulo #{chapter.id}...")
        QuizProject.Jobs.run(fn -> run_chapter_curation(chapter, user, opts) end)
        {:ok, chapter}

      :error ->
        {:error, :already_processing}
    end
  end

  defp start_chapter_curation(chapter) do
    Chapter
    |> Ash.Query.filter(id == ^chapter.id)
    |> Ash.Query.filter(curation_status != :processing)
    |> Ash.Query.filter(curation_status != :done or is_nil(curated_material_id))
    |> Ash.bulk_update(:start_curation, %{},
      authorize?: false,
      return_records?: true,
      return_errors?: true
    )
    |> case do
      %Ash.BulkResult{records: [updated]} -> {:ok, updated}
      _ -> :error
    end
  end

  defp run_chapter_curation(chapter, user, opts) do
    {status, material_id, usage} = create_and_curate(chapter, user, opts)

    finished =
      chapter
      |> Ash.Changeset.for_update(
        :finish_curation,
        %{
          curation_status: status,
          curated_material_id: material_id,
          usage_input_tokens: usage && usage.input,
          usage_output_tokens: usage && usage.output,
          curated_model: usage && Keyword.get(opts, :model)
        },
        authorize?: false
      )
      |> Ash.update!()

    Logger.info("[Books] Curadoria do capítulo #{finished.id} concluída como #{status}.")

    Phoenix.PubSub.broadcast(
      QuizProject.PubSub,
      ingest_topic(chapter.material_id),
      {:chapter_curated, %{chapter_id: finished.id}}
    )
  end

  # `:processing` só sai desse estado por `finish_curation`, chamado por quem
  # chama esta função — uma exceção não tratada aqui dentro deixaria o capítulo
  # travado pra sempre, sem caminho de volta pela UI (o filtro de
  # `start_chapter_curation/1` exclui justamente `:processing`). Por isso o
  # pipeline inteiro roda protegido, e qualquer falha, prevista ou não, vira
  # `:failed` em vez de propagar.
  defp create_and_curate(chapter, user, opts) do
    case QuizProject.AdaptiveStudy.create_material(user, %{
           title: chapter_material_title(chapter),
           raw_content: chapter_text_for_curation(chapter.id),
           status: "draft"
         }) do
      {:ok, material} ->
        try do
          case QuizProject.AdaptiveStudy.curate_material_with_ai(material, user, opts) do
            {:ok, updated_material, usage} ->
              demarcate_leaves(chapter, updated_material)
              {:done, updated_material.id, usage}

            {:error, _reason} ->
              discard_material(chapter, material, user)
          end
        rescue
          error ->
            log_unexpected_failure(chapter, error, __STACKTRACE__)
            discard_material(chapter, material, user)
        end

      {:error, reason} ->
        Logger.error(
          "[Books] Falha ao criar material para o capítulo #{chapter.id}: #{inspect(reason)}"
        )

        {:failed, nil, nil}
    end
  rescue
    error ->
      log_unexpected_failure(chapter, error, __STACKTRACE__)
      {:failed, nil, nil}
  end

  # Grava a demarcação de cada nó folha sobre os blocos que a IA apontou.
  # `chapter.material_id` é o material do LIVRO — é nele que os blocos e o
  # índice de `demarcate/4` vivem — e não o `material_id` do material de texto
  # gerado para a curadoria, que só existe para carregar o mapa mental.
  defp demarcate_leaves(chapter, material) do
    valid_positions = chapter.id |> list_blocks() |> MapSet.new(& &1.position)

    material.mindmap_tree
    |> Map.get("nodes", [])
    |> leaf_nodes()
    |> Enum.each(&demarcate_leaf(chapter, valid_positions, &1))
  end

  defp demarcate_leaf(chapter, valid_positions, node) do
    requested = node["blocks"] || []
    positions = Enum.filter(requested, &(is_integer(&1) and MapSet.member?(valid_positions, &1)))
    invalid = requested -- positions

    if invalid != [] do
      Logger.warning(
        "[Books] Capítulo #{chapter.id}: nó #{inspect(node["id"])} referenciou posições " <>
          "inválidas #{inspect(invalid)}, descartadas."
      )
    end

    if positions != [] do
      demarcate(chapter.material_id, node["id"], positions)
    end
  end

  defp leaf_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      case node["children"] do
        children when is_list(children) and children != [] -> leaf_nodes(children)
        _ -> [node]
      end
    end)
  end

  defp leaf_nodes(_), do: []

  # A tentativa fracassada não deixa lixo na Estudo Adaptativo: sem isso, cada
  # novo clique em "tentar novamente" empilharia mais um material de estudo
  # órfão, nunca referenciado por nenhum capítulo.
  defp discard_material(chapter, material, user) do
    case QuizProject.AdaptiveStudy.delete_material(material, user) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[Books] Falha ao apagar material órfão #{material.id} do capítulo #{chapter.id}: #{inspect(reason)}"
        )
    end

    {:failed, nil, nil}
  end

  defp log_unexpected_failure(chapter, error, stacktrace) do
    Logger.error(
      "[Books] Curadoria do capítulo #{chapter.id} falhou inesperadamente: " <>
        Exception.format(:error, error, stacktrace)
    )
  end

  defp chapter_material_title(chapter) do
    case String.trim(chapter.title) do
      "" -> "Capítulo #{chapter.position} curado"
      title -> "Capítulo: #{title}"
    end
  end

  @doc """
  Estado do processamento de IA do capítulo para a barra de leitura.

  `:done` só conta com `curated_material_id` presente: se o material gerado for
  apagado pela curadoria, a referência cai para `nil` (`on_delete: :nilify`) e o
  capítulo volta a poder ser reprocessado em vez de ficar com um link morto.
  """
  def chapter_ai_state(%Chapter{curation_status: :done, curated_material_id: id})
      when not is_nil(id),
      do: :done

  def chapter_ai_state(%Chapter{curation_status: status}) when status in [:processing, :failed],
    do: status

  def chapter_ai_state(%Chapter{}), do: :none

  @doc """
  Capítulo cuja curadoria de IA gerou este material de texto, se houver.

  É o caminho inverso de `curated_material_id`: a tela de curadoria usa isto
  para saber se o `content` de um nó deve ser lido direto ou resolvido a
  partir dos blocos do livro (`blocks_for_node/2`) — `material.format` não
  serve para essa distinção, porque o material de texto gerado por capítulo
  tem o mesmo `format: :text` de um upload manual.
  """
  def chapter_for_curated_material(material_id) do
    Chapter
    |> Ash.Query.filter(curated_material_id == ^material_id)
    |> Ash.read_one(authorize?: false)
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

  @doc """
  Como `chapter_text/1`, mas preparado para a curadoria por IA: cada bloco sai
  marcado com `[#posição]` antes do conteúdo, para a IA devolver referências em
  vez de cópia do texto (ver `Books.demarcate/4`); bloco de código sai cercado,
  com legenda e anotações — `chapter_text/1` não pode carregar essa marcação
  sem deixar de ser a reconstrução verbatim que promete.
  """
  def chapter_text_for_curation(chapter_id) do
    chapter_id
    |> list_blocks()
    |> Enum.map_join(@separator, &curation_text/1)
  end

  defp curation_text(%Block{type: :code} = block) do
    body =
      [block.caption, code_fence(block), annotations_list(block.annotations)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    "[##{block.position}]\n#{body}"
  end

  defp curation_text(%Block{position: position, content: content}) do
    "[##{position}]\n#{content}"
  end

  defp code_fence(%Block{lang: lang, content: content}), do: "```#{lang}\n#{content}\n```"

  defp annotations_list([]), do: nil
  defp annotations_list(annotations), do: Enum.map_join(annotations, "\n", &("- " <> &1))

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

  # Marcação e notas

  @doc "Cores de marcação disponíveis."
  def highlight_colors, do: Highlight.colors()

  @doc """
  Marcações de um capítulo, agrupadas por bloco: `%{block_id => [marcação]}`.

  Mesma forma de `coverage/1`, e pelo mesmo motivo — é o mapa que o cliente lê
  para desenhar as marcas ao montar o capítulo, sem varrer texto no servidor.
  Ordenadas por `start_offset` porque duas marcações no mesmo bloco desenham
  na ordem em que aparecem no texto.
  """
  def list_highlights(chapter_id, user_id) do
    Highlight
    |> Ash.Query.filter(chapter_id == ^chapter_id and user_id == ^user_id)
    |> Ash.Query.sort(start_offset: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.block_id)
  end

  @doc """
  Todas as marcações e notas do usuário num livro, para a lista "Minhas
  anotações" — mais recentes primeiro.

  Capítulo e posição do bloco chegam num mapa à parte, montado com duas
  consultas para o livro inteiro (o mesmo desenho de `library_progress/2`),
  em vez de um join por linha.
  """
  def list_highlights_for_material(user_id, material_id) do
    highlights =
      Highlight
      |> Ash.Query.filter(user_id == ^user_id and material_id == ^material_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(authorize?: false)

    chapters = material_id |> list_chapters() |> Map.new(&{&1.id, &1})

    block_positions =
      Block
      |> Ash.Query.filter(id in ^Enum.map(highlights, & &1.block_id))
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1.position})

    Enum.map(highlights, fn highlight ->
      %{
        highlight: highlight,
        chapter: Map.get(chapters, highlight.chapter_id),
        block_position: Map.get(block_positions, highlight.block_id)
      }
    end)
  end

  @doc """
  Marca um trecho de um bloco, com nota opcional.

  `block_position` é a posição absoluta que o cliente já tem em
  `data-position` — resolvida aqui, e não recebida como uuid, porque o bloco
  nunca chega ao cliente com o próprio id como valor confiável de evento (o
  data-attribute existe para outra coisa e trocar de capítulo não invalida o
  clique já em voo).

  Bloco de código não marca: a seleção ali serve para copiar o trecho exato,
  e o cliente já nem mostra a barra de marcação em cima dele — aqui é só a
  mesma regra valendo para quem manda o evento direto pelo socket.
  """
  def create_highlight(user, chapter, block_position, attrs) do
    with %Block{type: type} = block when type != :code <-
           Enum.find(list_blocks(chapter.id), &(&1.position == block_position)) do
      Highlight
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(attrs, %{
          user_id: user.id,
          material_id: chapter.material_id,
          chapter_id: chapter.id,
          block_id: block.id
        }),
        authorize?: false
      )
      |> Ash.create()
    else
      nil -> {:error, :block_not_found}
      %Block{} -> {:error, :unsupported_block_type}
    end
  end

  @doc "Busca uma marcação do usuário, para garantir que só o dono edita ou apaga."
  def get_own_highlight(id, user_id) do
    case Ash.get(Highlight, id, authorize?: false) do
      {:ok, %Highlight{user_id: ^user_id} = highlight} -> {:ok, highlight}
      {:ok, _} -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Atualiza a nota e/ou a cor de uma marcação já validada como do usuário."
  def update_highlight(highlight, attrs) do
    highlight
    |> Ash.Changeset.for_update(:update, attrs, authorize?: false)
    |> Ash.update()
  end

  # `Ash.destroy/2` devolve `:ok` ou `{:ok, resultado}` dependendo da ação —
  # ver `AdaptiveStudy.delete_material/2`, que já lida com as duas formas.
  # Normalizado aqui para `:ok` | `{:error, motivo}`, então quem chama nunca
  # precisa casar as duas.
  @doc "Remove uma marcação já validada como do usuário."
  def delete_highlight(highlight) do
    case Ash.destroy(highlight, authorize?: false) do
      :ok -> :ok
      {:ok, _} -> :ok
      error -> error
    end
  end
end
