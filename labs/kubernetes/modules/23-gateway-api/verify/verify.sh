#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab-gateway

# Check Gateway Controller
if ! kubectl get gatewayclass eg >/dev/null 2>&1; then
  fail "GatewayClass 'eg' is missing. Did you run the bootstrap script?"
fi

# Check Gateway: ждём Programmed по-настоящему (Envoy-проксе нужно
# отскейлиться и принять конфиг; на нагруженном стенде это 30-120с).
# Одноразовый warn здесь приводил к флаки: verify уходил дальше и curl
# зависал на NodePort, у которого ещё нет бэкендов.
require_resource lab-gateway gateway demo-gateway
GW_STATUS=""
for _ in $(seq 1 36); do
  GW_STATUS=$(kubectl get gateway demo-gateway -n lab-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  [[ "$GW_STATUS" == "True" ]] && break
  sleep 5
done
[[ "$GW_STATUS" == "True" ]] || fail "Gateway demo-gateway не стал Programmed за 180с"
ok "Gateway demo-gateway is Programmed"

# Check HTTPRoute
require_resource lab-gateway httproute store-route

# Check Deployments
require_deployment_ready lab-gateway store-v1 120s
require_deployment_ready lab-gateway store-v2 120s

# Verify traffic split weights
WEIGHT_V1=$(kubectl get httproute store-route -n lab-gateway -o jsonpath='{.spec.rules[0].backendRefs[0].weight}' 2>/dev/null || true)
WEIGHT_V2=$(kubectl get httproute store-route -n lab-gateway -o jsonpath='{.spec.rules[0].backendRefs[1].weight}' 2>/dev/null || true)

if [[ "$WEIGHT_V1" == "90" && "$WEIGHT_V2" == "10" ]]; then
  ok "HTTPRoute configured with 90/10 traffic split"
else
  warn "HTTPRoute traffic split weights are not 90/10 (found v1=$WEIGHT_V1, v2=$WEIGHT_V2)"
fi

# Verify actual routing: curl ИЗНУТРИ кластера на ClusterIP Envoy-сервиса.
# NodePort с внутренними GCP-IP отсюда недостижим (рабочая машина не в VPC) —
# хостовый curl давал ложные FAIL/зависания; in-cluster проверка детерминирована.
EG_SVC_IP=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-namespace=lab-gateway,gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
  -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)

if [[ -n "$EG_SVC_IP" ]]; then
  RES=""
  for _ in {1..12}; do
    RES=$(kubectl -n lab-gateway run curl-probe-23 --image=curlimages/curl:8.11.1 \
      --restart=Never --rm -i --quiet --timeout=60s -- -s -m 5 "http://${EG_SVC_IP}/store" 2>/dev/null || true)
    if echo "$RES" | grep -q "Store V"; then break; fi
    kubectl -n lab-gateway delete pod curl-probe-23 --ignore-not-found >/dev/null 2>&1
    sleep 5
  done
  if echo "$RES" | grep -q "Store V"; then
    ok "HTTPRoute is successfully routing traffic to /store (in-cluster)"
  else
    fail "HTTPRoute failed to route traffic to /store (Got: $RES)"
  fi
else
  warn "Could not determine Envoy service ClusterIP to verify HTTPRoute traffic"
fi

ok "module 23 verified"
