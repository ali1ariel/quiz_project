defmodule Mix.Tasks.Study.Export do
  @moduledoc """
  Exporta material(is) de estudo (linhas de banco + imagens) para um bundle
  `.tar.gz`, para enviar ao servidor com `scripts/sync_content.sh`.

      mix study.export --email dev@local.test
      mix study.export --email dev@local.test --output /tmp/bundle.tar.gz
      mix study.export --email dev@local.test --material ID1 --material ID2

  Sem `--material`, exporta todos os materiais do usuário.
  """
  use Mix.Task

  @shortdoc "Exporta materiais de estudo (dados + imagens) para um bundle .tar.gz"

  @switches [email: :string, output: :string, material: :keep]
  @aliases [e: :email, o: :output, m: :material]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    email = opts[:email] || Mix.raise("--email é obrigatório")
    output = opts[:output] || "content_bundle.tar.gz"
    material_ids = Keyword.get_values(opts, :material)

    case QuizProject.AdaptiveStudy.ContentBundle.export(email, material_ids, output) do
      {:ok, path, ids} ->
        Mix.shell().info("Bundle criado em #{path} (#{length(ids)} material(is))")

      {:error, :no_materials} ->
        Mix.raise("Nenhum material encontrado para #{email}")
    end
  end
end
