defmodule QuizProjectWeb.PageController do
  use QuizProjectWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def api_docs(conn, _params) do
    render(conn, :api_docs, page_title: "Documentação da API - Quizzes")
  end
end
