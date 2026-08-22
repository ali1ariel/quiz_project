defmodule QuizProject.Repo.Migrations.BackfillNodeBlocksChapterId do
  @moduledoc """
  Preenche `node_blocks.chapter_id` a partir do `chapter_id` do bloco que cada
  linha referencia — determinístico e sem ambiguidade, já que todo `block_id`
  pertence a exatamente um capítulo, para sempre (`blocks.chapter_id` é
  obrigatório e nunca é alterado depois de criado).
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE node_blocks nb
    SET chapter_id = b.chapter_id
    FROM blocks b
    WHERE nb.block_id = b.id
      AND nb.chapter_id IS NULL
    """)
  end

  def down do
    :ok
  end
end
