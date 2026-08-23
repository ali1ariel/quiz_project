#!/bin/bash
set -e

# Nível 1: NÃO paramos nem apagamos a release que está no ar. A nova release
# chega prebuildada do CI e só é ativada no final (start_application). Aqui só
# preparamos o diretório de staging que vai receber os arquivos.
APP_DIR="/opt/quiz_project"

echo "Preparing directories..."
mkdir -p "$APP_DIR/staging" "$APP_DIR/releases"

# Limpa apenas o staging (restos de um deploy anterior que tenha falhado).
# releases/ e o symlink current/ — a versão no ar — ficam intactos.
echo "Cleaning staging (leaving live release untouched)..."
rm -rf "$APP_DIR/staging"/* "$APP_DIR/staging"/.[!.]* 2>/dev/null || true

# Migração única do layout antigo: até aqui, cada deploy mandava o repo
# inteiro pra $APP_DIR e compilava na instância, deixando esses caminhos
# soltos na raiz. Lista por nome (nunca `rm -rf $APP_DIR/*`) pra não arriscar
# apagar staging/, releases/, current/ ou scripts/ por engano. erl_crash.dump
# fica de fora de propósito — é usado pra investigar quedas em produção.
echo "Cleaning up legacy source-based deploy layout (one-time)..."
rm -rf \
  "$APP_DIR/mix.exs" "$APP_DIR/mix.lock" \
  "$APP_DIR/deps" "$APP_DIR/_build" \
  "$APP_DIR/lib" "$APP_DIR/priv" "$APP_DIR/config" "$APP_DIR/assets" "$APP_DIR/test" \
  "$APP_DIR/README.md" "$APP_DIR/AGENTS.md"

chown -R ubuntu:ubuntu "$APP_DIR/staging" "$APP_DIR/releases"

echo "before_install completed"
exit 0
