defmodule QuizProjectWeb.Mcp.Server do
  @moduledoc """
  Servidor MCP (Model Context Protocol) sobre o transporte Streamable HTTP.

  Implementa o subconjunto stateless do protocolo: `initialize`, `ping`,
  `tools/list` e `tools/call` como mensagens JSON-RPC 2.0 em um único POST.
  Notificações e respostas do cliente são aceitas sem corpo (HTTP 202).
  """

  alias QuizProjectWeb.Mcp.Tools

  @default_protocol_version "2025-06-18"
  @supported_protocol_versions ["2025-06-18", "2025-03-26", "2024-11-05"]

  @server_info %{name: "quiz_project", title: "Quiz Project", version: "0.1.0"}
  @instructions "Ferramentas para criar, editar, validar e publicar quizzes " <>
                  "do usuário autenticado. Espelham a API JSON em /api/v1."

  @doc """
  Processa uma mensagem JSON-RPC já decodificada.

  Retorna `{:reply, resposta}` para requisições ou `:accepted` para
  notificações e respostas enviadas pelo cliente.
  """
  def handle(%{"_json" => messages}, _user, _token) when is_list(messages) do
    {:reply, error_response(nil, -32600, "Lotes JSON-RPC não são suportados")}
  end

  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, user, token) do
    case Map.fetch(message, "id") do
      {:ok, id} when not is_nil(id) ->
        {:reply, dispatch(method, Map.get(message, "params", %{}), id, user, token)}

      _ ->
        :accepted
    end
  end

  # Respostas do cliente (resultado de requisições iniciadas pelo servidor).
  def handle(%{"jsonrpc" => "2.0", "id" => _id} = message, _user, _token)
      when is_map_key(message, "result") or is_map_key(message, "error") do
    :accepted
  end

  def handle(message, _user, _token) do
    {:reply, error_response(Map.get(message, "id"), -32600, "Requisição JSON-RPC inválida")}
  end

  defp dispatch("initialize", params, id, _user, _token) do
    result(id, %{
      protocolVersion: negotiate_version(params["protocolVersion"]),
      capabilities: %{tools: %{listChanged: false}},
      serverInfo: @server_info,
      instructions: @instructions
    })
  end

  defp dispatch("ping", _params, id, _user, _token), do: result(id, %{})

  defp dispatch("tools/list", _params, id, _user, _token) do
    result(id, %{tools: Tools.definitions()})
  end

  defp dispatch("tools/call", %{"name" => name} = params, id, user, token) do
    case Tools.call(name, Map.get(params, "arguments", %{}), user, token.scopes) do
      {:ok, tool_result} -> result(id, tool_result)
      {:error, :unknown_tool} -> error_response(id, -32602, "Ferramenta desconhecida: #{name}")
    end
  end

  defp dispatch("tools/call", _params, id, _user, _token) do
    error_response(id, -32602, "O parâmetro name é obrigatório")
  end

  defp dispatch(method, _params, id, _user, _token) do
    error_response(id, -32601, "Método não encontrado: #{method}")
  end

  defp negotiate_version(requested) when requested in @supported_protocol_versions,
    do: requested

  defp negotiate_version(_requested), do: @default_protocol_version

  defp result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp error_response(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
