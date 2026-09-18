#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
kubectl get ns platform >/dev/null 2>&1 || fail "namespace/platform не найден"

require_resource platform networkpolicy default-deny
require_resource platform networkpolicy allow-dns
require_resource platform resourcequota platform-quota
require_resource platform limitrange platform-limits
require_resource platform role platform-admin
require_resource platform rolebinding platform-admin-binding

kubectl auth can-i create deployments -n platform --as=alice --as-group=platform-admins >/dev/null 2>&1 || fail "RBAC: участник группы platform-admins должен уметь создавать Deployment в platform"
if kubectl auth can-i create deployments -n platform --as=bob >/dev/null 2>&1; then
  fail "RBAC: пользователь вне группы platform-admins не должен создавать Deployment в platform"
fi
if kubectl auth can-i delete namespaces --as=alice --as-group=platform-admins >/dev/null 2>&1; then
  fail "RBAC: роль platform-admin не должна давать прав на удаление namespace"
fi
ok "RBAC: platform-admins могут управлять workload'ами, чужие и cluster-scope — нет"

kubectl -n platform delete pod verify-root verify-ok --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
if kubectl -n platform run verify-root --image=nginx:1.27-alpine --restart=Never >/dev/null 2>&1; then
  kubectl -n platform delete pod verify-root --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
  fail "PSA: под с root-контейнером должен быть отклонён профилем restricted"
fi
ok "PSA restricted: root-под отклонён"

kubectl -n platform apply -f - >/dev/null <<'EOF' || fail "совместимый с restricted под должен создаваться (LimitRange подставляет requests/limits)"
apiVersion: v1
kind: Pod
metadata:
  name: verify-ok
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
REQ=$(kubectl -n platform get pod verify-ok -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || true)
[[ "$REQ" == "100m" ]] || fail "LimitRange: под без resources должен получить defaultRequest cpu=100m, получил '${REQ:-пусто}'"
kubectl -n platform delete pod verify-ok --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
ok "LimitRange подставляет значения по умолчанию, квота считает их"

if [ -x "$(dirname "$0")/../audit/namespace-audit.sh" ]; then
  "$(dirname "$0")/../audit/namespace-audit.sh" || fail "audit-скрипт нашёл нарушения"
fi

ok "project-a verified"
