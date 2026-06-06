#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

TARGET_PATH="${1:-}"
if [[ -z "$TARGET_PATH" ]]; then
  echo "usage: $0 modules/<module-name>|projects/<project-name>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FULL_PATH="$ROOT_DIR/$TARGET_PATH"

if [[ ! -d "$FULL_PATH" ]]; then
  echo "Directory not found: $FULL_PATH"
  exit 1
fi

# --- Cleanup через trap: выполняется ВСЕГДА на выходе, в т.ч. при SIGTERM от
# `timeout` в sweep.sh. Раньше cleanup стоял в конце линейно — при зависании и
# kill'е модуля он НЕ срабатывал, оставляя residue (ns окружений, Argo, VAP). ---
CLEANED=0
do_cleanup() {
  [[ "$CLEANED" == 1 ]] && return 0
  CLEANED=1
  set +e
  if [[ -x "$ROOT_DIR/scripts/clean/clean-module.sh" ]]; then
    # clean-module.sh делает удаление манифестов + module cleanup.sh + generic
    # safety-net (CR/secret/VAP/Argo/доп-namespaces).
    bash "$ROOT_DIR/scripts/clean/clean-module.sh" "$TARGET_PATH"
  else
    [[ -d "$FULL_PATH/manifests" ]]      && kubectl -n lab delete -f "$FULL_PATH/manifests" --ignore-not-found=true 2>/dev/null
    [[ -d "$FULL_PATH/applicationset" ]] && kubectl -n lab delete -f "$FULL_PATH/applicationset" --ignore-not-found=true 2>/dev/null
    [[ -d "$FULL_PATH/overlays/prod" ]]  && kubectl -n lab delete -k "$FULL_PATH/overlays/prod" --ignore-not-found=true 2>/dev/null
  fi
  # Подстраховка lab (быстро, не блокирует).
  kubectl -n lab delete all --all 2>/dev/null
  return 0
}
trap do_cleanup EXIT
# SIGTERM (от timeout) / Ctrl-C → выход с кодом 124, что ТРИГГЕРИТ trap EXIT (cleanup).
trap 'exit 124' TERM INT

echo "--- Running module: $TARGET_PATH ---"

# Prepare
if [[ -f "$FULL_PATH/verify/prepare.sh" ]]; then
  echo "Running prepare.sh..."
  bash "$FULL_PATH/verify/prepare.sh"
fi

# Deploy
if [[ -d "$FULL_PATH/manifests" ]]; then
  if [[ -f "$FULL_PATH/manifests/kustomization.yaml" || -f "$FULL_PATH/manifests/kustomization.yml" ]]; then
    kubectl apply -k "$FULL_PATH/manifests"
  else
    kubectl apply -f "$FULL_PATH/manifests" -R
  fi
elif [[ -d "$FULL_PATH/applicationset" ]]; then
  kubectl apply -k "$FULL_PATH/applicationset" 2>/dev/null || kubectl apply -f "$FULL_PATH/applicationset"
elif [[ -d "$FULL_PATH/overlays/prod" ]]; then
  kubectl apply -k "$FULL_PATH/overlays/prod"
fi

# Wait a bit for resources to be created in API server
sleep 5

# Verify (не валим скрипт на ошибке — нужен код для отчёта; cleanup сделает trap)
set +e
bash "$FULL_PATH/verify/verify.sh"
VERIFY_EXIT=$?
set -e

exit "$VERIFY_EXIT"
