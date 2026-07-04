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
end
