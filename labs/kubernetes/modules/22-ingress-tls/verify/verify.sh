#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Бэкенды Части 1
require_deployment_ready lab web-a 120s
require_deployment_ready lab web-b 120s

# Routing-Ingress существует и привязан к классу nginx
require_resource lab ingress web-routing
CLASS=$(kubectl -n lab get ingress web-routing -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || true)
[[ "$CLASS" == "nginx" ]] || fail "ingress/web-routing ingressClassName='$CLASS', expected 'nginx'"

# Контроллер — обязательная зависимость модуля (без него Ingress не работает)
if kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  require_deployment_ready ingress-nginx ingress-nginx-controller 120s
else
  fail "ingress-nginx-controller не установлен (scripts/bootstrap/03-install-ingress.sh)"
fi
ok "ingress-nginx controller ready + web-routing(class=nginx)"

# Часть 3 (cert-manager): Certificate auto-tls выпущен (Ready) -> Secret создан САМ.
# Мягко: если cert-manager не поставлен, это не валит модуль (Части 1-2 не зависят).
if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  CR=$(kubectl -n lab get certificate auto-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "$CR" == "True" ]] && kubectl -n lab get secret auto-tls >/dev/null 2>&1; then
    ok "cert-manager: Certificate/auto-tls Ready + Secret/auto-tls создан автоматически"
  else
    warn "cert-manager есть, но Certificate/auto-tls ещё не Ready (примените manifests/cert-manager/ и подождите)"
  fi
else
  warn "cert-manager не установлен — Часть 3 пропущена (scripts/bootstrap/07-install-cert-manager.sh)"
fi

ok "module 22 verified"
