#!/usr/bin/env bash
# ПОЛНЫЙ СНОС стенда: terraform destroy (VM + диски; сеть/фаерволы тоже).
# Кластер и все данные на нём будут потеряны. Пересоздание — scripts/cluster/up.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/cluster-kubespray"

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Точно снести ВЕСЬ стенд (terraform destroy)? Введите 'yes': " ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "Отменено."; exit 1; }
fi

GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
export GOOGLE_OAUTH_ACCESS_TOKEN
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
echo "Стенд снесён. Пересоздание: scripts/cluster/up.sh (~25 мин)."
