defmodule QuizProject.Store.ImageStore do
  @moduledoc """
  Imagens de produto da Wish Store em disco, uma pasta por produto — mesmo
  racional do `QuizProject.AdaptiveStudy.ImageStore`: bytes fora do
  Postgres, para não gastar conexão do pool (recurso para consulta
  transacional) transportando estático.

  O nome gravado é um UUID gerado aqui, nunca o nome do arquivo enviado —
  evita colisão entre produtos e corta qualquer caminho vindo do cliente
  antes mesmo dele chegar no disco.
  """

  @doc "Raiz configurada do armazenamento."
  def root, do: Application.fetch_env!(:quiz_project, :store_images_dir)

  @doc """
  Grava os bytes de uma imagem e devolve o caminho relativo (a guardar em
  `ProductImage.path`): `<product_id>/<uuid><extensão>`.
  """
  def put(product_id, extension, data) do
    relative = Path.join(to_string(product_id), Ash.UUID.generate() <> extension)
    destination = Path.join(root(), relative)

    destination |> Path.dirname() |> File.mkdir_p!()
    File.write!(destination, data)

    relative
  end

  @doc """
  Caminho absoluto e tipo de conteúdo de uma imagem, para o controlador
  servir. Devolve `:error` para caminho inexistente ou que tente sair da
  pasta raiz — o caminho vem do banco, mas é tratado como entrada não
  confiável do mesmo jeito.
  """
  def fetch(path) do
    with {:ok, absolute} <- safe_join(root(), path),
         true <- File.regular?(absolute) do
      {:ok, absolute, content_type_for(path)}
    else
      _ -> :error
    end
  end

  @doc "Apaga o arquivo de uma imagem, se existir."
  def delete(path) do
    case safe_join(root(), path) do
      {:ok, absolute} -> File.rm(absolute)
      :error -> :ok
    end

    :ok
  end

  defp content_type_for(path) do
    case path |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".webp" -> "image/webp"
      ".gif" -> "image/gif"
      _ -> "application/octet-stream"
    end
  end

  # `Path.safe_relative/1` recusa `..` e caminho absoluto. A checagem do
  # prefixo depois dele é redundante de propósito: é a última linha entre o
  # banco e o sistema de arquivos.
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
