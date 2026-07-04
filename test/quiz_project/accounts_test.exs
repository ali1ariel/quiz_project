defmodule QuizProject.AccountsTest do
  use QuizProject.DataCase, async: true

  alias QuizProject.Accounts
  alias QuizProject.Accounts.User

  describe "registro" do
    test "cria usuário com e-mail e senha válidos" do
      assert {:ok, user} =
               Accounts.register_user(
                 %{email: "a@b.com", name: "Alisson", password: "senha12345"},
                 authorize?: false
               )

      assert to_string(user.email) == "a@b.com"
      assert user.hashed_password != "senha12345"
    end

    test "rejeita senha curta" do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register_user(%{email: "a@b.com", password: "curta"}, authorize?: false)
    end

    test "rejeita e-mail inválido" do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register_user(%{email: "invalido", password: "senha12345"},
                 authorize?: false
               )
    end

    test "rejeita e-mail duplicado, inclusive com caixa diferente" do
      assert {:ok, _} =
               Accounts.register_user(%{email: "a@b.com", password: "senha12345"},
                 authorize?: false
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.register_user(%{email: "A@B.com", password: "senha12345"},
                 authorize?: false
               )
    end
  end

  describe "autenticação" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "a@b.com", password: "senha12345"}, authorize?: false)

      %{user: user}
    end

    test "com credenciais corretas", %{user: user} do
      assert {:ok, authenticated} = User.authenticate("a@b.com", "senha12345")
      assert authenticated.id == user.id
    end

    test "com senha errada" do
      assert :error = User.authenticate("a@b.com", "senhaerrada")
    end

    test "com e-mail inexistente" do
      assert :error = User.authenticate("nao@existe.com", "senha12345")
    end
  end

  describe "tokens de API" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{email: "api@teste.com", password: "senha12345"},
          authorize?: false
        )

      %{user: user}
    end

    test "emite, autentica e revoga sem persistir o segredo puro", %{user: user} do
      assert {:ok, raw_token, record} = Accounts.issue_api_token(user, %{name: "Teste"})
      assert String.starts_with?(raw_token, "quiz_")
      assert record.name == "Teste"
      refute record.token_hash == raw_token

      assert {:ok, authenticated, authenticated_token} =
               Accounts.authenticate_api_token(raw_token)

      assert authenticated.id == user.id
      assert authenticated_token.id == record.id

      assert :ok = Accounts.revoke_api_token(record, user)
      assert :error = Accounts.authenticate_api_token(raw_token)
    end

    test "rejeita token expirado", %{user: user} do
      expires_at = DateTime.add(DateTime.utc_now(), -60, :second)
      assert {:ok, raw_token, _record} = Accounts.issue_api_token(user, %{expires_at: expires_at})
      assert :error = Accounts.authenticate_api_token(raw_token)
    end

    test "lista e revoga somente tokens do próprio usuário", %{user: user} do
      {:ok, _raw_token, token} = Accounts.issue_api_token(user, %{name: "Meu token"})

      {:ok, other} =
        Accounts.register_user(%{email: "outro-api@teste.com", password: "senha12345"},
          authorize?: false
        )

      assert [listed] = Accounts.list_api_tokens(user)
      assert listed.id == token.id
      assert {:error, :not_found} = Accounts.revoke_api_token(token.id, other)
      assert {:ok, revoked} = Accounts.revoke_api_token(token.id, user)
      assert revoked.id == token.id
      assert Accounts.list_api_tokens(user) == []
    end
  end

  describe "configurações da conta" do
    setup do
      {:ok, user} =
        Accounts.register_user(
          %{email: "perfil@teste.com", name: "Nome antigo", password: "senha12345"},
          authorize?: false
        )

      %{user: user}
    end

    test "atualiza nome e e-mail", %{user: user} do
      assert {:ok, updated} =
               Accounts.update_profile(user, %{name: "Nome novo", email: "novo@teste.com"})

      assert updated.name == "Nome novo"
      assert to_string(updated.email) == "novo@teste.com"
    end

    test "troca senha somente com a senha atual correta", %{user: user} do
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.change_password(user, "senha-errada", "nova-senha-123")

      assert {:ok, updated} = Accounts.change_password(user, "senha12345", "nova-senha-123")
      assert :error = User.authenticate("perfil@teste.com", "senha12345")
      assert {:ok, authenticated} = User.authenticate("perfil@teste.com", "nova-senha-123")
      assert authenticated.id == updated.id
    end
  end
end
