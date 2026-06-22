#!/usr/bin/env bash
set -euo pipefail

echo "==> Cleaning up Gateway API Lab..."

# Delete the namespace for the lab
kubectl delete namespace lab-gateway --ignore-not-found=true

# Delete the GatewayClass and EnvoyProxy config
kubectl delete gatewayclass eg --ignore-not-found=true
kubectl delete envoyproxy custom-proxy-config -n envoy-gateway-system --ignore-not-found=true

# Uninstall Envoy Gateway Controller and CRDs
# We use the same install URL used in bootstrap script to delete everything it created
kubectl delete --ignore-not-found=true -f https://github.com/envoyproxy/gateway/releases/download/v1.1.2/install.yaml

echo "==> Cleanup complete."
