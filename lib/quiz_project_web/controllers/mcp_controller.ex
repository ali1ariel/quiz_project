defmodule QuizProjectWeb.McpController do
  use QuizProjectWeb, :controller

  alias QuizProjectWeb.Mcp.Server

  def handle(conn, params) do
    case Server.handle(params, conn.assigns.current_user, conn.assigns.api_token) do
      {:reply, response} -> json(conn, response)
      :accepted -> send_resp(conn, :accepted, "")
    end
  end

  # O servidor é stateless e não abre streams SSE iniciados por GET,
  # nem mantém sessões encerráveis via DELETE.
  def method_not_allowed(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(:method_not_allowed, "")
  end
end
