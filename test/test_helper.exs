# O livro real da ingestão (23MB, obra comercial) não vai para o repositório,
# então os testes que dependem dele ficam de fora por padrão. Para rodá-los com
# o arquivo na máquina: `mix test --include epub_real`.
ExUnit.start(exclude: [:epub_real])
Ecto.Adapters.SQL.Sandbox.mode(QuizProject.Repo, :manual)
