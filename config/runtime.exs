import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/quiz_project start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :quiz_project, QuizProjectWeb.Endpoint, server: true
end

# As imagens dos livros são o único estado em disco da aplicação. Em produção o
# release fica em diretório recriado a cada deploy, então BOOK_IMAGES_DIR precisa
# apontar para um volume persistente; sem ele, os livros já enviados perderiam as
# figuras no próximo deploy e só voltariam com uma reingestão.
if config_env() == :prod do
  config :quiz_project,
         :book_images_dir,
         System.get_env("BOOK_IMAGES_DIR") || "/var/lib/quiz_project/book_images"

  config :quiz_project,
         :store_images_dir,
         System.get_env("STORE_IMAGES_DIR") || "/var/lib/quiz_project/store_images"
end

# Integração com IA: as API keys vêm de variáveis de ambiente do sistema
# (não por usuário no protótipo). AI_PROVIDER escolhe explicitamente
# ("openai", "gemini", "claude" ou "fake"); sem ela, usa o primeiro provider com
# chave configurada, caindo no Fake (heurística local) se não houver nenhuma.
if config_env() != :test do
  openai_key = System.get_env("OPENAI_API_KEY") || System.get_env("OPEN_AI_KEY")
  anthropic_key = System.get_env("ANTHROPIC_API_KEY")

  config :quiz_project,
    openai_api_key: openai_key,
    gemini_api_key: System.get_env("GEMINI_API_KEY"),
    anthropic_api_key: anthropic_key

  # Só sobrescreve o que veio do ambiente: o padrão de cada modelo mora em
  # `config.exs`, e repeti-lo aqui criaria dois lugares para desatualizar.
  for {var, chave} <- [
        {"OPENAI_MODEL", :openai_model},
        {"GEMINI_MODEL", :gemini_model},
        {"ANTHROPIC_MODEL", :anthropic_model}
      ],
      valor = System.get_env(var),
      valor != "" do
    config :quiz_project, [{chave, valor}]
  end

  ai_provider =
    case System.get_env("AI_PROVIDER") do
      "openai" ->
        QuizProject.AI.OpenAI

      "gemini" ->
        QuizProject.AI.Gemini

      provider when provider in ["claude", "anthropic"] ->
        QuizProject.AI.Claude

      "fake" ->
        QuizProject.AI.Fake

      nil ->
        # Claude entra por último na detecção automática para que quem já tinha
        # OPENAI_API_KEY ou GEMINI_API_KEY exportada continue no mesmo provider.
        cond do
          openai_key not in [nil, ""] -> QuizProject.AI.OpenAI
          System.get_env("GEMINI_API_KEY") not in [nil, ""] -> QuizProject.AI.Gemini
          anthropic_key not in [nil, ""] -> QuizProject.AI.Claude
          true -> QuizProject.AI.Fake
        end

      other ->
        raise "AI_PROVIDER inválido: #{inspect(other)}. Use \"openai\", \"gemini\", \"claude\" ou \"fake\"."
    end

  config :quiz_project, ai_provider: ai_provider

  # Quem pode disparar processamento de IA (custo real por chamada) vem do
  # AWS SSM Parameter Store, não do banco da aplicação — é a conta AWS quem
  # decide, não uma tela do produto. AI_AUTHORIZATION força o módulo
  # ("ssm" ou "fake"); sem ela, usa SSM só quando há credencial AWS
  # configurada, e cai no Fake (lista fixa abaixo) quando não há — do
  # contrário todo mundo que desenvolve sem acesso à conta AWS veria o botão
  # de IA sempre desativado.
  aws_access_key_id = System.get_env("AWS_ACCESS_KEY_ID")
  aws_secret_access_key = System.get_env("AWS_SECRET_ACCESS_KEY")

  config :ex_aws,
    access_key_id: aws_access_key_id,
    secret_access_key: aws_secret_access_key,
    region: System.get_env("AWS_REGION") || "us-east-1"

  if parameter = System.get_env("AI_AUTHORIZATION_PARAMETER") do
    config :quiz_project, ai_authorization_parameter: parameter
  end

  ai_authorization =
    case System.get_env("AI_AUTHORIZATION") do
      "ssm" ->
        QuizProject.AI.Authorization.SSM

      "fake" ->
        QuizProject.AI.Authorization.Fake

      nil ->
        if aws_access_key_id not in [nil, ""] and aws_secret_access_key not in [nil, ""] do
          QuizProject.AI.Authorization.SSM
        else
          QuizProject.AI.Authorization.Fake
        end

      other ->
        raise "AI_AUTHORIZATION inválido: #{inspect(other)}. Use \"ssm\" ou \"fake\"."
    end

  config :quiz_project, ai_authorization: ai_authorization

  # Só entra em uso quando `ai_authorization` cai no Fake (sem credencial
  # AWS). Sem nenhum e-mail fixo aqui — o repositório é público, e quem
  # desenvolve sem acesso à conta AWS libera o próprio e-mail exportando
  # AI_AUTHORIZATION_EMAILS localmente (nunca commitado).
  fake_emails =
    case System.get_env("AI_AUTHORIZATION_EMAILS") do
      nil -> []
      "" -> []
      emails -> String.split(emails, ",")
    end

  config :quiz_project, fake_authorized_emails: fake_emails
end

# Sincronização com o Google Calendar: OAuth2 por usuário, cada um com seu
# próprio calendário secundário dedicado (ver `QuizProject.GoogleCalendar`).
# Sem GOOGLE_CLIENT_ID, a aba "Google Calendar" em Settings fica desativada
# e o renovador de watch channel (`GoogleCalendar.WatchRenewer`) não sobe.
if config_env() != :test do
  config :quiz_project,
    google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
    google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
    google_oauth_redirect_uri:
      System.get_env("GOOGLE_OAUTH_REDIRECT_URI") ||
        "https://#{System.get_env("PHX_HOST") || "localhost"}/settings/google/callback",
    google_calendar_webhook_url:
      System.get_env("GOOGLE_CALENDAR_WEBHOOK_URL") ||
        "https://#{System.get_env("PHX_HOST") || "localhost"}/api/google/calendar/webhook"

  if config_env() == :prod do
    calendar_token_encryption_key =
      System.get_env("CALENDAR_TOKEN_ENCRYPTION_KEY") ||
        raise """
        environment variable CALENDAR_TOKEN_ENCRYPTION_KEY is missing.
        You can generate one by calling: :crypto.strong_rand_bytes(32) |> Base.encode64()
        """

    if byte_size(Base.decode64!(calendar_token_encryption_key)) != 32 do
      raise "CALENDAR_TOKEN_ENCRYPTION_KEY precisa decodificar para exatamente 32 bytes"
    end

    config :quiz_project, calendar_token_encryption_key: calendar_token_encryption_key
  end
end

config :quiz_project, QuizProjectWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :quiz_project, QuizProject.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :quiz_project, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :quiz_project, QuizProjectWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :quiz_project, QuizProjectWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :quiz_project, QuizProjectWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :quiz_project, QuizProject.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
