defmodule QuizProject.AdaptiveStudy.ContentBundle do
  @moduledoc """
  Empacota material(is) de estudo — linhas de banco (`study_materials`,
  `chapters`, `blocks`, `node_blocks`) e as imagens em disco do livro — num
  único `.tar.gz`, para levar de uma máquina/ambiente a outro sem replicar
  banco inteiro.

  A cópia usa `Repo.insert_all/3` (em lotes) contra os módulos do Ash, não as
  actions normais nem `Ash.Seed` linha a linha: um livro grande tem milhares
  de blocos, e inserir um de cada vez dentro de uma única transação prende a
  conexão do pool tempo demais — foi o que estourou o timeout de 15s do
  DBConnection na primeira versão. `insert_all` casta os tipos pelo schema do
  Ash (`__schema__/1`, que o `AshPostgres.DataLayer` gera) sem rodar
  validação, hook ou default: é cópia de um estado que já existiu, não
  criação, então id, timestamps e o `curated_material_id` que aponta pra
  outro material precisam sobreviver exatamente como estão.
  """

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias QuizProject.AdaptiveStudy.{Block, Chapter, ImageStore, NodeBlock, StudyMaterial}
  alias QuizProject.Accounts.User
  alias QuizProject.Repo

  # Bem abaixo do limite de parâmetros do Postgres (65535): blocks tem ~11
  # colunas, então 500 linhas por lote ainda sobra bastante margem.
  @insert_chunk_size 500

  @doc """
  Exporta os materiais do usuário (por e-mail) para `output_path`.

  Sem `material_ids`, exporta todos os materiais do usuário. Capítulos cuja
  curadoria gerou outro material (`curated_material_id`) puxam esse material
  junto — senão o `.tar.gz` teria uma referência que não existe do outro lado.
  """
  def export(email, material_ids, output_path) when is_binary(email) and is_list(material_ids) do
    user = find_user_by_email!(email)

    base_ids =
      case material_ids do
        [] -> user_material_ids(user.id)
        ids -> ids
      end

    all_ids = base_ids |> expand_related_materials() |> MapSet.to_list()

    if all_ids == [] do
      {:error, :no_materials}
    else
      do_export(all_ids, output_path)
    end
  end

  @doc """
  Importa um bundle gerado por `export/3` para dentro de `user`.

  Substitui integralmente os materiais contidos no bundle (mesmo `id`) — os
  registros antigos caem por `ON DELETE CASCADE` antes da reinserção, então
  rodar duas vezes com o mesmo bundle é seguro.
  """
  def import(archive_path, %User{} = user) do
    tmp_dir = stage_dir("import")
    tar_extract(archive_path, tmp_dir)

    manifest = tmp_dir |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    material_ids = manifest["study_materials"] |> Enum.map(& &1["id"])

    {:ok, _} =
      Repo.transaction(fn ->
        delete_existing(material_ids)
        insert_manifest(manifest, user.id)
      end)

    restore_images(material_ids, Path.join(tmp_dir, "images"))
    File.rm_rf!(tmp_dir)

    {:ok, length(material_ids)}
  end

  # -- export -----------------------------------------------------------

  defp do_export(material_ids, output_path) do
    materials = materials_by_ids(material_ids)
    chapters = chapters_by_material_ids(material_ids)
    blocks = blocks_by_chapter_ids(Enum.map(chapters, & &1.id))
    node_blocks = node_blocks_by_block_ids(Enum.map(blocks, & &1.id))

    manifest = %{
      "version" => 1,
      "exported_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "study_materials" => Enum.map(materials, &to_json_map(StudyMaterial, &1)),
      "chapters" => Enum.map(chapters, &to_json_map(Chapter, &1)),
      "blocks" => Enum.map(blocks, &to_json_map(Block, &1)),
      "node_blocks" => Enum.map(node_blocks, &to_json_map(NodeBlock, &1))
    }

    tmp_dir = stage_dir("export")
    File.write!(Path.join(tmp_dir, "manifest.json"), Jason.encode!(manifest))
    copy_images(material_ids, Path.join(tmp_dir, "images"))

    output_path |> Path.dirname() |> File.mkdir_p!()
    tar_create(tmp_dir, output_path)
    File.rm_rf!(tmp_dir)

    {:ok, output_path, material_ids}
  end

  defp expand_related_materials(ids), do: expand_related_materials(ids, MapSet.new())
  defp expand_related_materials([], seen), do: seen

  defp expand_related_materials(ids, seen) do
    new_ids = Enum.reject(ids, &MapSet.member?(seen, &1))

    if new_ids == [] do
      seen
    else
      seen = Enum.into(new_ids, seen)

      curated_ids =
        new_ids
        |> chapters_by_material_ids()
        |> Enum.map(& &1.curated_material_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      expand_related_materials(curated_ids, seen)
    end
  end

  defp user_material_ids(user_id) do
    StudyMaterial
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp materials_by_ids(ids),
    do: StudyMaterial |> Ash.Query.filter(id in ^ids) |> Ash.read!(authorize?: false)

  defp chapters_by_material_ids(ids),
    do: Chapter |> Ash.Query.filter(material_id in ^ids) |> Ash.read!(authorize?: false)

  defp blocks_by_chapter_ids(ids),
    do: Block |> Ash.Query.filter(chapter_id in ^ids) |> Ash.read!(authorize?: false)

  defp node_blocks_by_block_ids(ids),
    do: NodeBlock |> Ash.Query.filter(block_id in ^ids) |> Ash.read!(authorize?: false)

  defp copy_images(material_ids, images_dir) do
    File.mkdir_p!(images_dir)

    Enum.each(material_ids, fn id ->
      src = ImageStore.material_dir(id)
      if File.dir?(src), do: File.cp_r!(src, Path.join(images_dir, id))
    end)
  end

  # -- import -----------------------------------------------------------

  defp delete_existing(material_ids) do
    # Um DELETE só; `on_delete: :delete` em chapters/blocks/node_blocks cuida
    # do resto direto no banco.
    Repo.delete_all(from m in StudyMaterial, where: m.id in ^material_ids)
  end

  defp insert_manifest(manifest, user_id) do
    materials =
      manifest["study_materials"]
      |> Enum.map(&Map.put(&1, "user_id", user_id))
      |> Enum.map(&from_json_map(StudyMaterial, &1))

    insert_all_chunked(StudyMaterial, materials)
    insert_all_chunked(Chapter, Enum.map(manifest["chapters"], &from_json_map(Chapter, &1)))
    insert_all_chunked(Block, Enum.map(manifest["blocks"], &from_json_map(Block, &1)))

    insert_all_chunked(
      NodeBlock,
      Enum.map(manifest["node_blocks"], &from_json_map(NodeBlock, &1))
    )
  end

  defp insert_all_chunked(_resource, []), do: :ok

  defp insert_all_chunked(resource, entries) do
    entries
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(&Repo.insert_all(resource, &1))
  end

  defp restore_images(material_ids, images_src) do
    Enum.each(material_ids, fn id ->
      src = Path.join(images_src, id)

      if File.dir?(src) do
        dest = ImageStore.material_dir(id)
        File.rm_rf!(dest)
        dest |> Path.dirname() |> File.mkdir_p!()
        File.cp_r!(src, dest)
      end
    end)
  end

  defp find_user_by_email!(email) do
    User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> raise "Usuário com e-mail #{email} não encontrado"
      user -> user
    end
  end

  # -- serialização -------------------------------------------------------
  # Percorre `Ash.Resource.Info.attributes/1` em vez de `Map.from_struct/1`
  # porque é a mesma lista que `Ash.Seed` usa do outro lado — evita depender de
  # o struct do Ash não carregar campos extras (`__meta__`, agregados, etc).

  defp to_json_map(resource, struct) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Map.new(fn attr -> {attr.name, encode_value(attr.type, Map.get(struct, attr.name))} end)
  end

  defp from_json_map(resource, json_map) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Map.new(fn attr ->
      {attr.name, decode_value(attr.type, Map.get(json_map, Atom.to_string(attr.name)))}
    end)
  end

  defp encode_value(_type, nil), do: nil
  defp encode_value(Ash.Type.Decimal, %Decimal{} = value), do: Decimal.to_string(value)
  defp encode_value(Ash.Type.UtcDatetimeUsec, %DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_value(Ash.Type.Atom, value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(_type, value), do: value

  defp decode_value(_type, nil), do: nil
  defp decode_value(Ash.Type.Decimal, value) when is_binary(value), do: Decimal.new(value)

  defp decode_value(Ash.Type.UtcDatetimeUsec, value) when is_binary(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp decode_value(Ash.Type.Atom, value) when is_binary(value),
    do: String.to_existing_atom(value)

  defp decode_value(_type, value), do: value

  # -- arquivo .tar.gz ------------------------------------------------------

  defp stage_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{Ash.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end

  defp tar_create(src_dir, dest_path) do
    {_output, 0} = System.cmd("tar", ["czf", dest_path, "-C", src_dir, "."])
    :ok
  end

  defp tar_extract(archive_path, dest_dir) do
    File.mkdir_p!(dest_dir)
    {_output, 0} = System.cmd("tar", ["xzf", archive_path, "-C", dest_dir])
    :ok
  end
end
