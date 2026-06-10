#!/usr/bin/env bash
# Фичи модуля требуют свежего Kubernetes: native sidecars GA 1.33,
# in-place resize beta 1.33 (subresource resize), scheduling gates GA 1.30.
# На старых кластерах манифесты отвергаются API-сервером с невнятными
# ошибками валидации — отсекаем заранее с понятным сообщением.
set -euo pipefail

MINOR=$(kubectl version -o json 2>/dev/null | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["serverVersion"]["minor"].rstrip("+"))')
if [[ "${MINOR:-0}" -lt 33 ]]; then
  echo "Модуль 29 требует Kubernetes >= 1.33 (native sidecars GA, in-place resize)."
  echo "Версия кластера: 1.${MINOR}. Обновите кластер или пропустите модуль."
  exit 1
fi
echo "prepare: k8s 1.${MINOR} >= 1.33 — ok"
