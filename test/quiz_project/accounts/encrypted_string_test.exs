defmodule QuizProject.Accounts.EncryptedStringTest do
  use ExUnit.Case, async: true

  alias QuizProject.Accounts.EncryptedString

  test "cast_input aceita string e nil" do
    assert {:ok, "segredo"} = EncryptedString.cast_input("segredo", [])
    assert {:ok, nil} = EncryptedString.cast_input(nil, [])
  end

  test "dump_to_native seguido de cast_stored recupera o valor original" do
    assert {:ok, stored} = EncryptedString.dump_to_native("token-secreto", [])
    assert {:ok, "token-secreto"} = EncryptedString.cast_stored(stored, [])
  end

  test "nil não é criptografado" do
    assert {:ok, nil} = EncryptedString.dump_to_native(nil, [])
    assert {:ok, nil} = EncryptedString.cast_stored(nil, [])
  end

  test "duas criptografias do mesmo valor produzem bytes diferentes (nonce aleatório)" do
    {:ok, a} = EncryptedString.dump_to_native("mesmo-valor", [])
    {:ok, b} = EncryptedString.dump_to_native("mesmo-valor", [])

    assert a != b
    assert {:ok, "mesmo-valor"} = EncryptedString.cast_stored(a, [])
    assert {:ok, "mesmo-valor"} = EncryptedString.cast_stored(b, [])
  end

  test "ciphertext adulterado falha ao decifrar em vez de devolver lixo" do
    {:ok, stored} = EncryptedString.dump_to_native("token-secreto", [])
    <<nonce::binary-12, tag::binary-16, ciphertext::binary>> = stored
    adulterado = <<nonce::binary-12, tag::binary-16, "x", ciphertext::binary>>

    assert :error = EncryptedString.cast_stored(adulterado, [])
  end
end
