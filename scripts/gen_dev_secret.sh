#!/bin/bash
# Gera config/dev.secret.exs a partir dos parâmetros de IA no AWS SSM.
# Útil para rodar localmente com as mesmas chaves de produção.
#
# Uso: scripts/gen_dev_secret.sh
set -euo pipefail

cd "$(dirname "$0")/.."

get_param_optional() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo ""
}

echo "Buscando parâmetros de IA no SSM..."
OPENAI_API_KEY=$(get_param_optional "/quiz_project/prod/openai_api_key")
GEMINI_API_KEY=$(get_param_optional "/quiz_project/prod/gemini_api_key")
AI_PROVIDER=$(get_param_optional "/quiz_project/prod/ai_provider")

cat > config/dev.secret.exs <<ELIXIR
import Config

config :quiz_project,
  openai_api_key: "${OPENAI_API_KEY}",
  gemini_api_key: "${GEMINI_API_KEY}"
ELIXIR

if [ -n "${AI_PROVIDER}" ]; then
  case "${AI_PROVIDER}" in
    openai) echo 'config :quiz_project, ai_provider: QuizProject.AI.OpenAI' >> config/dev.secret.exs ;;
    gemini) echo 'config :quiz_project, ai_provider: QuizProject.AI.Gemini' >> config/dev.secret.exs ;;
    fake)   echo 'config :quiz_project, ai_provider: QuizProject.AI.Fake' >> config/dev.secret.exs ;;
  esac
fi

echo "config/dev.secret.exs criado com sucesso!"
