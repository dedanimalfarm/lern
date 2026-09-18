#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"
NS=lab-gateway

need_bin kubectl
kubectl get gatewayclass eg >/dev/null 2>&1 || fail "нет GatewayClass eg — bash scripts/bootstrap/11-install-gateway-api.sh"
require_namespace "$NS"

kubectl -n "$NS" wait --for=condition=Programmed gateway/demo-gateway --timeout=180s >/dev/null || fail "Gateway demo-gateway не стал Programmed за 180s"
ok "Gateway demo-gateway: Programmed"

route_cond() { kubectl -n "$NS" get httproute "$1" -o jsonpath="{.status.parents[0].conditions[?(@.type==\"$2\")].status}" 2>/dev/null || true; }
for r in store-route header-route; do
  for _ in $(seq 1 24); do
    [[ "$(route_cond "$r" Accepted)" == "True" && "$(route_cond "$r" ResolvedRefs)" == "True" ]] && break
    sleep 5
  done
  [[ "$(route_cond "$r" Accepted)" == "True" ]] || fail "HTTPRoute $r: Accepted != True (reasons: $(kubectl -n "$NS" get httproute "$r" -o jsonpath='{.status.parents[0].conditions[*].reason}' 2>/dev/null || true))"
  [[ "$(route_cond "$r" ResolvedRefs)" == "True" ]] || fail "HTTPRoute $r: ResolvedRefs != True — backend не найден или порт неверный"
done
ok "HTTPRoute store-route и header-route: Accepted + ResolvedRefs"

BACKENDS=$(kubectl -n "$NS" get httproute store-route -o jsonpath='{.spec.rules[*].backendRefs[*].name}' 2>/dev/null || true)
[[ "$BACKENDS" == *store-v1* && "$BACKENDS" == *store-v2* ]] || fail "store-route должен вести на store-v1 и store-v2 (traffic splitting), сейчас: '$BACKENDS'"
require_deployment_ready "$NS" store-v1 120s
require_deployment_ready "$NS" store-v2 120s

GW=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[[ -n "$GW" ]] || fail "не найден Service data-plane Envoy для demo-gateway в ns envoy-gateway-system"
kubectl -n "$NS" delete pod verify-curl --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
OUT=$(kubectl -n "$NS" run verify-curl --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- sh -c "
  for i in \$(seq 1 60); do curl -s -m 5 http://$GW.envoy-gateway-system/store; echo; done
  echo UNKNOWN=\$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://$GW.envoy-gateway-system/unknown)
  echo BETA_NOHDR=\$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://$GW.envoy-gateway-system/beta)
  echo BETA=\$(curl -s -m 5 -H 'X-Beta-Access: true' http://$GW.envoy-gateway-system/beta)
" 2>/dev/null || true)
V1=$(grep -c 'Store V1' <<<"$OUT" || true)
V2=$(grep -c 'Store V2' <<<"$OUT" || true)
[[ "$V1" -gt 0 && "$V2" -gt 0 ]] || fail "traffic splitting: за 60 запросов V1=$V1 V2=$V2 — ожидали ответы обоих backend'ов (веса 90/10)"
[[ "$V1" -gt "$V2" ]] || fail "traffic splitting: V1=$V1 должно быть больше V2=$V2 при весах 90/10"
grep -q 'UNKNOWN=404' <<<"$OUT" || fail "/unknown должен отдавать 404 от Envoy, получили: $(grep 'UNKNOWN=' <<<"$OUT" || true)"
grep -q 'BETA_NOHDR=404' <<<"$OUT" || fail "/beta без заголовка должен отдавать 404, получили: $(grep 'BETA_NOHDR=' <<<"$OUT" || true)"
grep -q '^BETA=Store V1' <<<"$OUT" || fail "/beta с X-Beta-Access: true должен отдавать Store V1, получили: $(grep '^BETA=' <<<"$OUT" || true)"
ok "трафик через шлюз: /store V1=$V1 V2=$V2, /unknown -> 404, /beta -> по заголовку"

ok "module 23 verified"
