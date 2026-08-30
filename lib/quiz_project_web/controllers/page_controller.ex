defmodule QuizProjectWeb.PageController do
  use QuizProjectWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def api_docs(conn, _params) do
    render(conn, :api_docs, page_title: "Documentação da API - Quizzes")
  end

  def privacy(conn, _params) do
    render(conn, :privacy, page_title: "Política de Privacidade - Quizzes")
  end

  def terms(conn, _params) do
    render(conn, :terms, page_title: "Termos de Serviço - Quizzes")
  end
end
