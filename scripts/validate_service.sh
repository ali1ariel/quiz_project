#!/bin/bash
# Confere se o serviço subiu e está respondendo na porta HTTP.
PORT=4005

systemctl restart quiz_project.service

sleep 10

systemctl is-active quiz_project.service

# O serviço está aceitando conexões?
timeout 30 bash -c "until printf '' 2>>/dev/null >>/dev/tcp/localhost/${PORT}; do sleep 1; done"

exit 0
