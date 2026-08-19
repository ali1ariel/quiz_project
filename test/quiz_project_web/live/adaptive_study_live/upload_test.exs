defmodule QuizProjectWeb.AdaptiveStudyLive.UploadTest do
  # A lista de autorizados de IA vive em `Application.env` (estado global do
  # BEAM, ver `AI.Authorization.Fake`) — precisa rodar sozinho.
  use QuizProjectWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias QuizProject.AdaptiveStudy

  setup :register_and_log_in_user

  setup do
    on_exit(fn -> Application.put_env(:quiz_project, :fake_authorized_emails, []) end)
  end

  describe "usuário autorizado" do
    setup %{user: user} do
      Application.put_env(:quiz_project, :fake_authorized_emails, [to_string(user.email)])
      :ok
    end

    test "cria um material e segue para a curadoria", %{conn: conn, user: user} do
      {:ok, view_new, _html_new} = live(conn, ~p"/study/new")
      assert has_element?(view_new, "#upload-study-form")
      refute has_element?(view_new, "#submit-generate-mindmap[disabled]")

      view_new
      |> form("#upload-study-form", %{
        "title" => "Novo Material Teste",
        "raw_content" => "Este é o conteúdo do material de estudo em Elixir."
      })
      |> render_submit()

      [material] = AdaptiveStudy.list_materials(user)
      assert material.title == "Novo Material Teste"

      # Redireciona para /study/:id/curate
      {:ok, view_curate, html_curate} = live(conn, ~p"/study/#{material.id}/curate")
      assert html_curate =~ "Novo Material Teste"
      assert has_element?(view_curate, "#save-curation-btn")
      assert has_element?(view_curate, "#reconstruct-text-btn")
    end
  end

  describe "usuário não autorizado" do
    setup do
      Application.put_env(:quiz_project, :fake_authorized_emails, [])
      :ok
    end

    test "o botão de gerar mapa mental vem desabilitado", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/study/new")

      assert has_element?(view, "#submit-generate-mindmap[disabled]")
      assert html =~ "não está autorizado a processar conteúdo com IA"
    end

    # O botão desabilitado é a interface; a garantia é o servidor — o evento
    # chega pelo socket como chegaria de um cliente adulterado.
    test "o evento salvar direto pelo socket não cria material", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/study/new")

      render_submit(view, "save", %{
        "title" => "Não devia existir",
        "raw_content" => "Conteúdo qualquer."
      })

      assert AdaptiveStudy.list_materials(user) == []
    end
  end
end
