#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Running yamllint ==="
yamllint -c "$ROOT_DIR/.yamllint" "$ROOT_DIR/modules" "$ROOT_DIR/projects" || echo "Yamllint found issues."

echo "=== Running kubeconform ==="
find "$ROOT_DIR/modules" "$ROOT_DIR/projects" -type d -name "charts" -prune -o -type f \( -name "*.yaml" -o -name "*.yml" \) \
  ! -name "kustomization.yaml" ! -name "kustomization.yml" -print0 | \
  xargs -0 kubeconform -ignore-missing-schemas -strict || echo "Kubeconform found issues."

echo "=== Running shellcheck ==="
find "$ROOT_DIR/modules" "$ROOT_DIR/projects" "$ROOT_DIR/scripts" -type f -name "*.sh" -print0 | \
  xargs -0 shellcheck || echo "Shellcheck found issues."

echo "=== Running kustomize build ==="
find "$ROOT_DIR/modules" "$ROOT_DIR/projects" \( -name "kustomization.yaml" -o -name "kustomization.yml" \) -print0 | while IFS= read -r -d '' kfile; do
  dir="$(dirname "$kfile")"
  kubectl kustomize --load-restrictor LoadRestrictionsNone "$dir" >/dev/null || { echo "Kustomize build failed in $dir"; exit 1; }
done

echo "Done."
