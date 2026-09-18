#!/usr/bin/env bash
# Сценарий: платформенная команда завела namespace с PSA и квотой, но забыла LimitRange.
# Разработчик приносит обычный под без requests/limits — и получает отказ квоты,
# хотя «ресурсов полно». Под сделан совместимым с PSA restricted, чтобы единственной
# причиной отказа была именно квота.
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/quota.yaml
kubectl -n platform delete limitrange platform-limits --ignore-not-found

cat << 'EOF' | kubectl apply -f - || true
apiVersion: v1
kind: Pod
metadata:
  name: demo-app
  namespace: platform
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile: { type: RuntimeDefault }
  containers:
  - name: web
    image: nginxinc/nginx-unprivileged:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: { drop: ["ALL"] }
EOF

# Ожидаемый результат:
# Error from server (Forbidden): error when creating "STDIN": pods "demo-app" is forbidden:
#   failed quota: platform-quota: must specify limits.cpu for: web; limits.memory for: web;
#   requests.cpu for: web; requests.memory for: web
#
# Причина: квота с requests/limits требует, чтобы у КАЖДОГО контейнера они были заданы,
# а подставлять значения по умолчанию некому — LimitRange не применён.
#
# Решение: kubectl apply -f manifests/limitrange.yaml — и тот же под создастся,
# получив default/defaultRequest из LimitRange (проверьте: kubectl -n platform get pod demo-app
# -o jsonpath='{.spec.containers[0].resources}').
