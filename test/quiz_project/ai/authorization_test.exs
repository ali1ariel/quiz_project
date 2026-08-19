defmodule QuizProject.AI.AuthorizationTest do
  # A lista fica em `Application.env` (ver `AI.Authorization.Fake`), e
  # `contents_read_live_test.exs` mexe na mesma chave — os dois precisam
  # rodar um de cada vez.
  use ExUnit.Case, async: false

  alias QuizProject.AI.Authorization
  alias QuizProject.AI.Authorization.Fake

  setup do
    on_exit(fn -> Application.put_env(:quiz_project, :fake_authorized_emails, []) end)
  end

  describe "Fake" do
    test "autoriza só quem está na lista" do
      Application.put_env(:quiz_project, :fake_authorized_emails, ["alguem@exemplo.com"])

      assert Fake.authorized?("alguem@exemplo.com")
      refute Fake.authorized?("outro@exemplo.com")
    end

    test "compara sem diferenciar maiúscula/minúscula e ignora espaço nas pontas" do
      Application.put_env(:quiz_project, :fake_authorized_emails, ["Alguem@Exemplo.com"])

      assert Fake.authorized?("alguem@exemplo.com")
      assert Fake.authorized?("  ALGUEM@EXEMPLO.COM  ")
    end

    test "lista vazia não autoriza ninguém" do
      Application.put_env(:quiz_project, :fake_authorized_emails, [])

      refute Fake.authorized?("qualquer@coisa.com")
    end

    test "entrada que não é string nunca autoriza" do
      refute Fake.authorized?(nil)
      refute Fake.authorized?(123)
    end
  end

  describe "fachada" do
    test "usa a implementação configurada (Fake em teste)" do
      Application.put_env(:quiz_project, :fake_authorized_emails, ["alguem@exemplo.com"])

      assert Authorization.authorized?("alguem@exemplo.com")
      refute Authorization.authorized?("outro@exemplo.com")
    end
  end
end
