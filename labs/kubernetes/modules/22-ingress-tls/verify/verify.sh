#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

kubectl get ingressclass nginx >/dev/null 2>&1 || fail "нет IngressClass nginx — bash scripts/bootstrap/03-install-ingress.sh"
require_deployment_ready ingress-nginx ingress-nginx-controller 120s
require_deployment_ready lab web-a 120s
require_deployment_ready lab web-b 120s
ok "Part 1: ingress-nginx, web-a, web-b готовы"

for ing in web-routing web-paths; do
  kubectl -n lab get ingress "$ing" >/dev/null 2>&1 || fail "Ingress $ing не найден"
  CLS=$(kubectl -n lab get ingress "$ing" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || true)
  [[ "$CLS" == "nginx" ]] || fail "Ingress $ing: ingressClassName='$CLS', ожидали nginx"
done
ok "Part 1: Ingress web-routing и web-paths с классом nginx"

IC=http://ingress-nginx-controller.ingress-nginx
kubectl -n lab delete pod verify-curl --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
OUT=$(kubectl -n lab run verify-curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- sh -c "
  for i in \$(seq 1 24); do curl -s -m 3 -o /dev/null $IC/ -H 'Host: a.lab.local' && break; sleep 5; done
  echo A=\$(curl -s -m 5 $IC/ -H 'Host: a.lab.local')
  echo B=\$(curl -s -m 5 $IC/ -H 'Host: b.lab.local')
  echo PA=\$(curl -s -m 5 $IC/a -H 'Host: paths.lab.local')
  echo NOHOST=\$(curl -s -m 5 -o /dev/null -w '%{http_code}' $IC/)
  echo AUTO=\$(curl -sk -m 5 -o /dev/null -w '%{http_code}' --connect-to auto.lab.local:443:ingress-nginx-controller.ingress-nginx:443 https://auto.lab.local/)
" 2>/dev/null || true)
grep -q '^A=hello from web-a' <<<"$OUT" || fail "a.lab.local должен отдавать web-a, получили: $(grep '^A=' <<<"$OUT" || true)"
grep -q '^B=hello from web-b' <<<"$OUT" || fail "b.lab.local должен отдавать web-b, получили: $(grep '^B=' <<<"$OUT" || true)"
grep -q '^PA=hello from web-a' <<<"$OUT" || fail "paths.lab.local/a должен отдавать web-a (rewrite-target), получили: $(grep '^PA=' <<<"$OUT" || true)"
grep -q '^NOHOST=404' <<<"$OUT" || fail "запрос без известного Host должен попадать в default backend (404), получили: $(grep '^NOHOST=' <<<"$OUT" || true)"
ok "Part 1: маршрутизация по host и path через ingress-nginx"

if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  kubectl get clusterissuer selfsigned-issuer >/dev/null 2>&1 || fail "ClusterIssuer selfsigned-issuer не найден"
  kubectl -n lab get ingress auto-tls >/dev/null 2>&1 || fail "Ingress auto-tls не найден"
  kubectl -n lab wait --for=condition=Ready certificate/auto-tls --timeout=180s >/dev/null 2>&1 || fail "Certificate auto-tls не стал Ready за 180s: $(kubectl -n lab get certificate auto-tls -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true)"
  CRT=$(kubectl -n lab get secret auto-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
  [[ -n "$CRT" ]] || fail "Secret auto-tls без tls.crt — ingress-shim не выпустил сертификат"
  grep -q '^AUTO=200' <<<"$OUT" || fail "HTTPS auto.lab.local через ingress-nginx должен отдавать 200, получили: $(grep '^AUTO=' <<<"$OUT" || true)"
  ok "Part 3: cert-manager выпустил auto-tls, HTTPS auto.lab.local -> 200"
else
  warn "cert-manager не установлен — TLS-проверки пропущены (bash scripts/bootstrap/07-install-cert-manager.sh)"
fi

if kubectl -n lab get secret secure-tls >/dev/null 2>&1; then
  kubectl -n lab get ingress secure-tls >/dev/null 2>&1 || fail "Secret secure-tls есть, а Ingress secure-tls — нет"
  ok "Part 2: ручной TLS-секрет secure-tls и Ingress secure-tls на месте"
else
  warn "Part 2: Secret secure-tls не создан (ручной openssl-шаг из README) — пропущено"
fi

ok "module 22 verified"
