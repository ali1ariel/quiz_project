defmodule QuizProject.Aws.ReqHttpClient do
  @moduledoc """
  Cliente HTTP do `ex_aws` usando `Req`, para não trazer outra pilha HTTP
  (`hackney`) para o projeto — `Req` já é o cliente de todo o resto da
  aplicação (os providers de IA).

  Formato ditado pelo comportamento `ExAws.Request.HttpClient`, cuja própria
  documentação traz este adaptador como exemplo.
  """
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, _http_opts) do
    request = Req.new(decode_body: false, retry: false)

    case Req.request(request, method: method, url: url, body: body, headers: headers) do
      {:ok, response} ->
        {:ok,
         %{
           status_code: response.status,
           headers: Req.get_headers_list(response),
           body: response.body
         }}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
