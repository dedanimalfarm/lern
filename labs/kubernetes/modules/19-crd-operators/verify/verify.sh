#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
kubectl get crd webapps.lab.example.com >/dev/null 2>&1 || fail "CRD webapps.lab.example.com не найден"
require_resource lab webapp my-webapp
kubectl -n lab get wa my-webapp >/dev/null 2>&1 || fail "shortName wa из CRD не работает"
kubectl -n lab get webapp my-webapp -o wide 2>/dev/null | grep -q 'nginx:1.27-alpine' || fail "additionalPrinterColumns: колонки IMAGE/REPLICAS не показываются в kubectl get webapp"
ok "Part 1–2: CRD зарегистрирован, my-webapp есть, shortName и printer columns работают"

if kubectl -n lab apply --dry-run=server -f - >/dev/null 2>&1 <<'EOF'
apiVersion: lab.example.com/v1
kind: WebApp
metadata: { name: verify-bad-range, namespace: lab }
spec: { image: nginx:1.27-alpine, replicas: 0 }
EOF
then fail "схема CRD должна отклонять replicas=0 (minimum: 1), а приняла"; fi
if kubectl -n lab apply --dry-run=server -f - >/dev/null 2>&1 <<'EOF'
apiVersion: lab.example.com/v1
kind: WebApp
metadata: { name: verify-bad-required, namespace: lab }
spec: { replicas: 2 }
EOF
then fail "схема CRD должна отклонять spec без обязательного image, а приняла"; fi
ok "Part 2: openAPIV3Schema отбивает replicas=0 и отсутствие image"

kubectl -n lab patch webapp my-webapp --subresource=status --type=merge -p '{"status":{"availableReplicas":3}}' >/dev/null 2>&1 || fail "status subresource недоступен — в CRD нет subresources.status или kubectl старее 1.24"
[[ "$(kubectl -n lab get webapp my-webapp -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)" == "3" ]] || fail "запись в /status не сохранилась"
ok "Part 2: /status subresource принимает и хранит статус"

if kubectl -n webapp-operator get deploy webapp-operator >/dev/null 2>&1 || pgrep -f 'kopf run' >/dev/null 2>&1; then
  require_deployment_ready lab my-webapp-deploy 120s
  require_resource lab svc my-webapp-svc
  OWNER=$(kubectl -n lab get deploy my-webapp-deploy -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)
  [[ "$OWNER" == "WebApp" ]] || fail "у my-webapp-deploy ownerReference должен указывать на WebApp, сейчас '${OWNER:-нет}'"
  ok "Part 3: оператор создал my-webapp-deploy и my-webapp-svc с ownerReference на WebApp"
else
  warn "оператор не запущен — reconcile не проверяется (kopf run controller/operator.py -A или controller/manifests)"
fi

ok "module 19 verified"
