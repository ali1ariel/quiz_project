import Config
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Acelera hashing de senha nos testes
config :bcrypt_elixir, :log_rounds, 1

# Chave fixa só pra teste (mesma lógica do secret_key_base abaixo) — não
# precisa ser secreta, só precisa ter 32 bytes em base64.
config :quiz_project,
  :calendar_token_encryption_key,
  "Zm9vYmFyYmF6cXV1eGNvcmdlZ3JhdWx0Zm9vYmFyYmE="

# Credenciais falsas pra exercitar o fluxo OAuth do Google Calendar nos
# testes (chamadas reais são sempre stubadas via `Req.Test`, ver
# `:google_req_options`).
config :quiz_project,
  google_client_id: "test-client-id",
  google_client_secret: "test-client-secret",
  google_oauth_redirect_uri: "http://localhost:4002/settings/google/callback"

# Nos testes a IA é sempre o provider heurístico local
config :quiz_project, :ai_provider, QuizProject.AI.Fake

# Nos testes a autorização de IA é sempre a lista fixa (sem SSM, sem
# GenServer subindo) — vazia por padrão, e cada teste que precisa de alguém
# autorizado configura via `Application.put_env/3` no próprio `setup`.
config :quiz_project, :ai_authorization, QuizProject.AI.Authorization.Fake
config :quiz_project, :fake_authorized_emails, []

# Trabalho em background roda inline nos testes (sem concorrência nem
# dependência do sandbox de conexões)
config :quiz_project, :jobs_mode, :inline

# Cada execução da suíte escreve imagem num diretório temporário próprio, para
# não sujar priv/ nem herdar arquivo de uma execução anterior.
config :quiz_project,
       :book_images_dir,
       Path.join([System.tmp_dir!(), "quiz_project_test", "book_images"])

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :quiz_project, QuizProject.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "quiz_project_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :quiz_project, QuizProjectWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZVQcKRClMcJw2MbofL981TLftTMeZuduau0A633LuDzO85XrEg/dxytEKgOjPqN0",
  server: false

# In test we don't send emails
config :quiz_project, QuizProject.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Não sobe Chrome na suíte: a rota de card de preview cai no fallback estático.
config :quiz_project, enable_chromic_pdf: false
