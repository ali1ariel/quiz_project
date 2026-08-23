#!/bin/bash
set -e

# O start_application já reiniciou o serviço com a release nova — aqui NÃO
# reiniciamos de novo. Só validamos que a release nova subiu e está
# respondendo em :4005.
PORT=4005

echo "Waiting for service to become active..."
for _ in $(seq 1 15); do
  if systemctl is-active --quiet quiz_project.service; then
    break
  fi
  sleep 2
done
systemctl is-active quiz_project.service

echo "Probing /health on :${PORT} ..."
if ! timeout 30 bash -c "until curl -fsS http://localhost:${PORT}/health >/dev/null 2>&1; do sleep 1; done"; then
  echo "FATAL: /health did not return 200 within 30s"
  exit 1
fi

echo "validate_service OK"
exit 0
