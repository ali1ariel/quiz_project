#!/bin/bash
# Exporta material(is) de estudo do banco local (dados + imagens) e envia para
# produção via POST /api/v1/study/import — sem SSH, só o token de API.
#
# Uso:
#   STUDY_API_TOKEN=quiz_xxx scripts/sync_content.sh dev@local.test
#   STUDY_API_TOKEN=quiz_xxx scripts/sync_content.sh dev@local.test ID1 ID2
#
# Sem IDs de material, exporta tudo que o e-mail tem localmente. O token
# precisa do escopo `study:write` (gerado em Conta e API > Tokens).
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${QUIZ_PROJECT_HOST:-https://quizzes.alissonmachado.dev}"
EMAIL="${1:?Uso: scripts/sync_content.sh EMAIL [MATERIAL_ID...]}"
shift || true

if [ -z "${STUDY_API_TOKEN:-}" ]; then
  echo "Defina STUDY_API_TOKEN com um token de API (escopo study:write)." >&2
  exit 1
fi

BUNDLE="$(mktemp -u /tmp/content_bundle_XXXXXX.tar.gz)"
trap 'rm -f "$BUNDLE"' EXIT

MATERIAL_ARGS=()
for id in "$@"; do
  MATERIAL_ARGS+=(--material "$id")
done

echo "Exportando material(is) de $EMAIL..."
mix study.export --email "$EMAIL" --output "$BUNDLE" "${MATERIAL_ARGS[@]}"

echo "Enviando bundle para $HOST..."
curl -sSf \
  -H "Authorization: Bearer $STUDY_API_TOKEN" \
  -F "bundle=@${BUNDLE}" \
  "$HOST/api/v1/study/import"
echo

echo "Concluído."
