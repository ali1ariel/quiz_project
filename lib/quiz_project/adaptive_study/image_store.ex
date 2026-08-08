defmodule QuizProject.AdaptiveStudy.ImageStore do
  @moduledoc """
  Imagens do livro em disco, uma pasta por material.

  Fora do banco de propósito. Um livro técnico traz 21MB de imagem, e servi-las
  pelo Postgres gastaria uma conexão do pool por arquivo — recurso dimensionado
  para consulta transacional, não para transporte de bytes estáticos. Em disco o
  `send_file/3` entrega o trabalho ao kernel, sem copiar nada pela VM, e o dump
  do banco volta a ser só texto e metadados.

  O caminho de dentro do EPUB vira caminho relativo dentro da pasta do material,
  o que mantém a estrutura do livro legível para quem for depurar. Nem na
  gravação nem na leitura um caminho pode escapar dessa pasta.
  """

  alias QuizProject.Epub

  @doc "Raiz configurada do armazenamento."
  def root, do: Application.fetch_env!(:quiz_project, :book_images_dir)

  @doc "Pasta de um material."
  def material_dir(material_id), do: Path.join(root(), to_string(material_id))

  @doc """
  Grava as imagens do livro, substituindo o que houver.

  Reingerir troca o livro inteiro, então a pasta é limpa antes — senão a imagem
  de uma edição anterior ficaria órfã ocupando disco para sempre.
  """
  def put_all(material_id, images) when is_map(images) do
    delete_all(material_id)
    dir = material_dir(material_id)

    Enum.each(images, fn {path, %{data: data}} ->
      case safe_join(dir, path) do
        {:ok, destination} ->
          destination |> Path.dirname() |> File.mkdir_p!()
          File.write!(destination, data)

        :error ->
          :ok
      end
    end)
  end

  @doc """
  Caminho absoluto e tipo de conteúdo de uma imagem, para o controlador servir.

  Devolve `:error` para caminho que não existe ou que tenta sair da pasta do
  material — o caminho vem da URL, então ele é entrada não confiável.
  """
  def fetch(material_id, path) do
    with {:ok, absolute} <- safe_join(material_dir(material_id), path),
         true <- File.regular?(absolute),
         {:ok, content_type} <- Epub.image_content_type(path) do
      {:ok, absolute, content_type}
    else
      _ -> :error
    end
  end

  @doc "Apaga todas as imagens de um material."
  def delete_all(material_id) do
    material_id |> material_dir() |> File.rm_rf!()
    :ok
  end

  @doc "Bytes ocupados em disco por um material."
  def byte_size_of(material_id) do
    material_id
    |> material_dir()
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reduce(0, fn file, total ->
      case File.stat(file) do
        {:ok, %{type: :regular, size: size}} -> total + size
        _ -> total
      end
    end)
  end

  # `Path.safe_relative/1` recusa `..` e caminho absoluto. A checagem do prefixo
  # depois dele é redundante de propósito: é a última linha entre a URL e o
  # sistema de arquivos.
  defp safe_join(dir, path) do
    with {:ok, relative} <- Path.safe_relative(path),
         absolute = Path.expand(relative, dir),
         true <- String.starts_with?(absolute, Path.expand(dir) <> "/") do
      {:ok, absolute}
    else
      _ -> :error
    end
  end
end
