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

# Check Gateway
require_resource lab-gateway gateway demo-gateway
GW_STATUS=$(kubectl get gateway demo-gateway -n lab-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
[[ "$GW_STATUS" == "True" ]] || warn "Gateway demo-gateway is not yet Programmed"

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

# Verify actual routing via curl
NODE_PORT=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=lab-gateway,gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].spec.ports[0].nodePort}' 2>/dev/null || true)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}' || true)

if [[ -n "$NODE_PORT" && -n "$NODE_IP" ]]; then
  # Try to reach the endpoint, allowing some time for Envoy to configure
  SUCCESS=false
  for _ in {1..10}; do
    RES=$(curl -s "http://${NODE_IP}:${NODE_PORT}/store" || true)
    if echo "$RES" | grep -q "Store V"; then
      SUCCESS=true
      break
    fi
    sleep 2
  done
  if [[ "$SUCCESS" == "true" ]]; then
    ok "HTTPRoute is successfully routing traffic to /store"
  else
    fail "HTTPRoute failed to route traffic to /store (Got: $RES)"
  fi
else
  warn "Could not determine NodePort or NodeIP to verify HTTPRoute traffic"
fi

ok "module 23 verified"
