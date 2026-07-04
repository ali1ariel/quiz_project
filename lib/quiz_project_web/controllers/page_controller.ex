defmodule QuizProjectWeb.PageController do
  use QuizProjectWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
