#!/bin/bash
set -e
source /opt/quiz_project/scripts/check_db.sh

APP_DIR="/opt/quiz_project"
PORT=4005
PHX_HOST="quizzes.alissonmachado.dev"
BOOK_IMAGES_DIR="/var/lib/quiz_project/book_images"

get_param() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text
}

# Opcional: retorna vazio se o parâmetro não existir
get_param_optional() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo ""
}

echo "Fetching secrets from AWS Parameter Store..."
DB_URL=$(get_param "/quiz_project/prod/database_url")
KEY_BASE=$(get_param "/quiz_project/prod/secret_key_base")

# Integração com IA é opcional: sem chave, o app usa o provider Fake (heurística local).
OPENAI_API_KEY=$(get_param_optional "/quiz_project/prod/openai_api_key")
GEMINI_API_KEY=$(get_param_optional "/quiz_project/prod/gemini_api_key")
ANTHROPIC_API_KEY=$(get_param_optional "/quiz_project/prod/anthropic_api_key")
AI_PROVIDER=$(get_param_optional "/quiz_project/prod/ai_provider")

# Quem pode disparar processamento de IA (custo real por chamada). A app não
# tem credencial AWS em runtime, então lê a lista aqui — igual às chaves
# acima — em vez de usar o poller QuizProject.AI.Authorization.SSM, que
# exigiria AWS_ACCESS_KEY_ID/AWS_REGION no processo. Atualiza só a cada
# deploy, não a cada 5 minutos.
AI_AUTHORIZATION_EMAILS=$(get_param_optional "/quiz_project/prod/ai_authorized_emails")

# --- Promove a release prebuildada do staging para um diretório versionado ---
# A versão no ar (current/) segue intocada até a troca do symlink lá embaixo.
RELEASE_ID="$(date +%Y%m%d%H%M%S)"
RELEASE_DIR="$APP_DIR/releases/$RELEASE_ID"
NEW_BIN="$RELEASE_DIR/bin/quiz_project"

echo "Promoting staged release to $RELEASE_DIR ..."
mkdir -p "$APP_DIR/releases"
mv "$APP_DIR/staging" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/tmp"
chown -R ubuntu:ubuntu "$RELEASE_DIR"
chmod -R 755 "$RELEASE_DIR"

if [ ! -x "$NEW_BIN" ]; then
  echo "FATAL: promoted release binary not found at $NEW_BIN"
  exit 1
fi

# Journald só persiste entre reboots se este diretório existir — sem ele, um
# OOM kill que derruba a máquina (não só o processo) leva o log junto com o
# corpo do crime.
echo "Ensuring persistent journald storage..."
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true

# Único estado em disco da app (ver QuizProject.Application.ensure_book_images_dir!/0):
# precisa existir e pertencer a ubuntu *antes* do boot, já que o processo sobe
# como ubuntu e /var/lib é raiz de root.
sudo mkdir -p "$BOOK_IMAGES_DIR"
sudo chown -R ubuntu:ubuntu "$BOOK_IMAGES_DIR"
sudo chmod -R 755 "$BOOK_IMAGES_DIR"

# --- systemd aponta para o symlink estável current/ (não para releases/<id>) ---
echo "Writing systemd unit..."
sudo tee /etc/systemd/system/quiz_project.service >/dev/null <<EOL
[Unit]
Description=Quiz Project Service
After=network.target postgresql.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${APP_DIR}

# Application environment variables
Environment="PORT=${PORT}"
Environment="MIX_ENV=prod"
Environment="PHX_HOST=${PHX_HOST}"
Environment="PHX_SERVER=true"
Environment="POOL_SIZE=10"
Environment="RELEASE_NAME=quiz_project"
Environment="BOOK_IMAGES_DIR=${BOOK_IMAGES_DIR}"
Environment="DATABASE_URL=${DB_URL}"
Environment="SECRET_KEY_BASE=${KEY_BASE}"
Environment="OPENAI_API_KEY=${OPENAI_API_KEY}"
Environment="GEMINI_API_KEY=${GEMINI_API_KEY}"
Environment="ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
Environment="AI_PROVIDER=${AI_PROVIDER}"
Environment="AI_AUTHORIZATION_EMAILS=${AI_AUTHORIZATION_EMAILS}"

# Dump de post-mortem da VM em crash não-OOM (o BEAM tem tempo de escrever
# antes de morrer; um SIGKILL do OOM killer não tem, aí só resta o [vm] no
# journald de antes de cair).
Environment="ERL_CRASH_DUMP=${APP_DIR}/erl_crash.dump"
Environment="ERL_CRASH_DUMP_SECONDS=10"

ExecStart=${APP_DIR}/current/bin/quiz_project start
ExecStop=${APP_DIR}/current/bin/quiz_project stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 /etc/systemd/system/quiz_project.service
sudo systemctl daemon-reload

echo "Waiting for database to be ready..."
sleep 4

if ! check_database_connection "$DB_URL"; then
  echo "Cannot proceed - database is not accessible (a versão no ar segue intacta)"
  exit 1
fi

# --- Migra com a release NOVA, ANTES de girar o symlink ---
# Se a migração falhar, current/ ainda aponta para a versão antiga (que segue
# rodando) e o deploy é marcado como falho sem downtime.
echo "Running migrations with the new release..."
DATABASE_URL="${DB_URL}" SECRET_KEY_BASE="${KEY_BASE}" "$NEW_BIN" eval "QuizProject.Release.migrate"

# --- Troca atômica: gira o symlink e faz um único restart ---
# A janela de indisponibilidade fica limitada ao restart do BEAM (~poucos seg).
echo "Switching current -> $RELEASE_DIR"
ln -sfn "$RELEASE_DIR" "$APP_DIR/current"
chown -h ubuntu:ubuntu "$APP_DIR/current"

sudo systemctl enable quiz_project
sudo systemctl restart quiz_project

echo "Waiting for service to start..."
sleep 5
sudo systemctl status quiz_project --no-pager || true

# --- Limpa releases antigas, mantendo as 3 mais recentes ---
echo "Pruning old releases (keeping the 3 newest)..."
cd "$APP_DIR/releases"
ls -1dt */ 2>/dev/null | tail -n +4 | xargs -r rm -rf

echo "start_application completed"
