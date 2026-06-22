#!/usr/bin/env bash
set -euo pipefail

echo "==> Verifying Gateway API Lab..."

# Check that the GatewayClass exists
if ! kubectl get gatewayclass eg &> /dev/null; then
  echo "Error: GatewayClass 'eg' not found."
  exit 1
fi

# Check that the Gateway exists
if ! kubectl get gateway demo-gateway -n lab-gateway &> /dev/null; then
  echo "Error: Gateway 'demo-gateway' not found in namespace 'lab-gateway'."
  exit 1
fi

# Check if Gateway is Programmed
echo "Waiting for Gateway to be Programmed..."
kubectl wait --timeout=10s -n lab-gateway gateway/demo-gateway --for=condition=Programmed || {
  echo "Warning: Gateway is not Programmed yet or timed out."
}

# Check that HTTPRoute exists
if ! kubectl get httproute store-route -n lab-gateway &> /dev/null; then
  echo "Error: HTTPRoute 'store-route' not found."
  exit 1
fi

# Check that store-v2 is present in HTTPRoute backendRefs
BACKEND_REFS=$(kubectl get httproute store-route -n lab-gateway -o jsonpath='{.spec.rules[*].backendRefs[*].name}')
if [[ "$BACKEND_REFS" != *"store-v1"* || "$BACKEND_REFS" != *"store-v2"* ]]; then
  echo "Error: HTTPRoute 'store-route' does not route to both store-v1 and store-v2. Did you complete the Traffic Splitting part?"
  exit 1
fi

# Check that backend pods are running
V1_PODS=$(kubectl get pods -n lab-gateway -l app=store,version=v1 -o jsonpath='{.items[*].status.phase}')
if [[ "$V1_PODS" != *"Running"* ]]; then
  echo "Error: store-v1 pod is not Running."
  exit 1
fi

V2_PODS=$(kubectl get pods -n lab-gateway -l app=store,version=v2 -o jsonpath='{.items[*].status.phase}')
if [[ "$V2_PODS" != *"Running"* ]]; then
  echo "Error: store-v2 pod is not Running."
  exit 1
fi

echo "==> Verification successful! Lab completed."
