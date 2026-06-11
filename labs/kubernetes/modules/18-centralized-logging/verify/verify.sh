#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Wait for loki and promtail to be ready
require_deployment_ready lab loki 60s
kubectl -n lab rollout status daemonset/promtail --timeout=60s >/dev/null

# Let it scrape some logs
sleep 15

# Check if Loki is accessible and responding
if kubectl -n lab exec deploy/loki -- wget -qO- http://localhost:3100/loki/api/v1/status/buildinfo >/dev/null 2>&1; then
  ok "loki is ready"
else
  warn "loki is not ready"
  exit 1
fi

ok "module 18 verified"
