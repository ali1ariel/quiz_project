defmodule QuizProject.Accounts.EncryptedString do
  @moduledoc """
  String criptografada em repouso (AES-256-GCM) — usada pelos tokens OAuth do
  Google Calendar (`GoogleCalendarConnection`), que precisam ser recuperáveis
  para chamar a API do Google de volta (diferente de `ApiToken.token_hash`,
  que só precisa ser comparável, nunca lido em claro).

  Formato armazenado: `nonce (12 bytes) <> tag (16 bytes) <> ciphertext`.
  Chave em `:calendar_token_encryption_key` (base64, 32 bytes) — ver
  `config/runtime.exs`.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :binary

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_binary(value), do: {:ok, value}
  def cast_input(_, _), do: :error

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(<<nonce::binary-12, tag::binary-16, ciphertext::binary>>, _) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, "", tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(value, _) when is_binary(value) do
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, value, "", 16, true)

    {:ok, nonce <> tag <> ciphertext}
  end

  def dump_to_native(_, _), do: :error

  @impl true
  def matches_type?(value, _), do: is_binary(value) or is_nil(value)

  defp key do
    :quiz_project
    |> Application.fetch_env!(:calendar_token_encryption_key)
    |> Base.decode64!()
  end
end
