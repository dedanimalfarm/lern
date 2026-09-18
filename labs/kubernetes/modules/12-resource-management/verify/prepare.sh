#!/usr/bin/env bash
set -euo pipefail

kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab >/dev/null
for kind in limitrange/lab-limits resourcequota/lab-quota; do
  if kubectl -n lab get "$kind" >/dev/null 2>&1; then
    kubectl -n lab delete "$kind" >/dev/null
    echo "prepare: $kind снят на время модуля — с ним под без resources либо получает defaultRequest (Burstable вместо BestEffort), либо отбивается квотой; cleanup вернёт его"
  fi
done
echo "prepare: namespace lab готов (без базовых quota/LimitRange — их ставит Часть 4)"
