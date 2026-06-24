#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning up Module 16 resources..."

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Delete module-specific resources in lab namespace
kubectl -n lab delete -f "$DIR/manifests/vault/vso-secrets.yaml" --ignore-not-found
kubectl -n lab delete -f "$DIR/manifests/vault/vault-pg.yaml" -f "$DIR/manifests/vault/rbac.yaml" --ignore-not-found
kubectl -n lab delete -f "$DIR/manifests/eso/eso-fake.yaml" --ignore-not-found
kubectl -n lab delete sealedsecret app-creds --ignore-not-found
kubectl -n lab delete secret app-creds pg-dynamic-creds db-from-eso etcd-probe --ignore-not-found
kubectl delete clusterrolebinding vault-token-reviewer --ignore-not-found

# sealed-secrets, External Secrets Operator и Vault Secrets Operator — это
# PERSISTENT-аддоны стенда (ставятся scripts/cluster/up.sh --addons и
# bootstrap/08–10; prepare.sh модуля их НЕ ставит, а рассчитывает на готовые).
# Их НЕЛЬЗЯ деинсталлировать в cleanup модуля: раньше этот скрипт сносил CRD/ns
# всех трёх операторов, из-за чего повторный прогон m16 падал в prepare
# («no matches for kind SealedSecret/VaultConnection»), а полный sweep ронял и
# зависящие модули. Операторы должны переживать прогон модуля.
echo "Cleanup complete (persistent-аддоны sealed-secrets/ESO/VSO сохранены)."
