#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# Ждём пока кластер my-db будет готов (условие Ready)
kubectl -n lab wait --for=condition=Ready cluster/my-db --timeout=400s

# Ждём поды db-client
require_deployment_ready lab db-client 60s

ok "module 21 verified"
