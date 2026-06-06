#!/usr/bin/env bash
set -e

echo "==> Installing Envoy Gateway (Gateway API implementation)..."
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.1.2/install.yaml

echo "==> Waiting for Envoy Gateway controller..."
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

echo "==> Creating EnvoyProxy config (NodePort) and GatewayClass 'eg'..."
cat <<EOF | kubectl apply -f -
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: custom-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: custom-proxy-config
    namespace: envoy-gateway-system
EOF

echo "==> Done. Gateway API is ready."
