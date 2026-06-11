#!/usr/bin/env bash
# Остаточная уборка модуля 30 (вызывается clean-module.sh ПОСЛЕ удаления
# manifests/). Здесь: одноразовые Job'ы из extras/ и восстановление исходного
# datasource Loki модуля 18 — наш loki-datasource-v2 (с derivedFields) удалён
# вместе с манифестами, и без восстановления модуль 18 остался бы без datasource.
set +e

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl -n lab delete job telemetrygen-direct telemetrygen-via-collector \
  --ignore-not-found=true 2>/dev/null

# clean-module.sh удаляет манифесты с -n lab — ресурсы в ДРУГОМ namespace
# (datasource-секреты в monitoring) он удалить не может, добиваем здесь.
kubectl -n monitoring delete secret tempo-datasource --ignore-not-found=true 2>/dev/null

M18_DS="$MODULE_DIR/../18-centralized-logging/manifests/datasource.yaml"
if [[ -f "$M18_DS" ]] && kubectl get ns monitoring >/dev/null 2>&1; then
  kubectl apply -f "$M18_DS" >/dev/null 2>&1 \
    && echo "cleanup: исходный loki-datasource (модуль 18) восстановлен"
fi

exit 0
