#!/usr/bin/env bash
# Остановка VM стенда (диски и кластер сохраняются; платим только за диски,
# ~$4/мес вместо ~$73/мес). ВНИМАНИЕ: при следующем старте сменятся внешние
# IP — поднимать стенд через scripts/cluster/start.sh (он всё обновит).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/cluster-kubespray"

PROJECT="$(terraform -chdir="$TF_DIR" output -raw project_id 2>/dev/null \
  || python3 -c "import re;print(re.search(r'project_id\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"
ZONE="$(terraform -chdir="$TF_DIR" output -raw zone 2>/dev/null \
  || python3 -c "import re;print(re.search(r'\"zone\"\s*\{[^}]*default\s*=\s*\"([^\"]+)',open('$TF_DIR/variables.tf').read(),re.S).group(1))")"
mapfile -t NODE_NAMES < <(terraform -chdir="$TF_DIR" output -json nodes \
  | python3 -c 'import json,sys;[print(k) for k in json.load(sys.stdin)]')

echo "Останавливаю VM: ${NODE_NAMES[*]} (project=$PROJECT zone=$ZONE)"
gcloud compute instances stop "${NODE_NAMES[@]}" --zone="$ZONE" --project="$PROJECT"
echo "Остановлено. Поднять обратно: scripts/cluster/start.sh"
