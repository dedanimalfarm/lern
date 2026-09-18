#!/usr/bin/env bash
set -euo pipefail
kubectl create namespace team-x --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace team-x-dev --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata: { name: hierarchy, namespace: team-x-dev }
spec: { parent: team-x }
YAML
echo "team-x-dev вложен в team-x. Теперь «наследуем» team-x от team-x-dev:"
set +e
kubectl apply -f - <<'YAML'
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata: { name: hierarchy, namespace: team-x }
spec: { parent: team-x-dev }
YAML
