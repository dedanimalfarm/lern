#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

require_namespace lab
require_resource lab rollout demo-rollout
require_resource lab svc demo-rollout-svc

# Wait for Rollout to become healthy
kubectl argo rollouts status demo-rollout -n lab --timeout=120s >/dev/null || fail "Rollout is not healthy"

ok "module 24 verified"
