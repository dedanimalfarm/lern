#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_deployment_ready lab web 120s
require_deployment_ready lab api 120s
require_deployment_ready lab db 120s

# Все пять политик должны существовать
for np in default-deny allow-dns web-egress api-policy db-policy; do
  require_resource lab networkpolicy "$np"
done

# Предупредить, если CNI не умеет enforcement (тогда политики декоративны)
if kubectl -n kube-system get pods 2>/dev/null | grep -qiE "calico|cilium"; then
  ok "CNI with NetworkPolicy enforcement detected (calico/cilium)"
else
  warn "no calico/cilium found — NetworkPolicy may NOT be enforced on this cluster"
fi

ok "module 15 verified"
