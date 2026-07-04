#!/bin/bash
set -e
source /opt/quiz_project/scripts/check_db.sh

APP_DIR="/opt/quiz_project"
BIN="$APP_DIR/_build/prod/rel/quiz_project/bin/quiz_project"
PORT=4005
PHX_HOST="quizzes.alissonmachado.dev"

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
AI_PROVIDER=$(get_param_optional "/quiz_project/prod/ai_provider")

echo "Setting up directory permissions..."
sudo mkdir -p "$APP_DIR/_build/prod/rel/quiz_project/tmp"
sudo chown -R ubuntu:ubuntu "$APP_DIR/_build/prod/rel/quiz_project/tmp"
sudo chmod -R 755 "$APP_DIR/_build/prod/rel/quiz_project/tmp"

echo "Creating systemd service file..."
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
Environment="DATABASE_URL=${DB_URL}"
Environment="SECRET_KEY_BASE=${KEY_BASE}"
Environment="OPENAI_API_KEY=${OPENAI_API_KEY}"
Environment="GEMINI_API_KEY=${GEMINI_API_KEY}"
Environment="AI_PROVIDER=${AI_PROVIDER}"

ExecStart=${BIN} start
ExecStop=${BIN} stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

echo "Setting proper permissions..."
sudo chmod 644 /etc/systemd/system/quiz_project.service

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Waiting for database to be ready..."
sleep 4

if ! check_database_connection "$DB_URL"; then
  echo "Cannot proceed with deployment - database is not accessible"
  exit 1
fi

echo "Running migrations..."
DATABASE_URL="${DB_URL}" SECRET_KEY_BASE="${KEY_BASE}" "$BIN" eval "QuizProject.Release.migrate"

echo "Enabling and starting quiz_project service..."
sudo systemctl enable quiz_project
sudo systemctl restart quiz_project

echo "Waiting for service to start..."
sleep 5

echo "Checking service status..."
sudo systemctl status quiz_project --no-pager
