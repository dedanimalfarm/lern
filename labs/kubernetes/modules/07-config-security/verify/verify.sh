#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab
require_resource lab sa pod-reader
# RBAC-кэш авторизатора в apiserver обновляется асинхронно: auth can-i сразу
# после применения Role/RoleBinding может ответить "no" на свежие права.
sleep 2

can_get=$(kubectl -n lab auth can-i get pods --as=system:serviceaccount:lab:pod-reader || true)
[[ "$can_get" == "yes" ]] || fail "serviceaccount pod-reader cannot get pods"

can_delete=$(kubectl -n lab auth can-i delete pods --as=system:serviceaccount:lab:pod-reader || true)
[[ "$can_delete" == "no" ]] || fail "serviceaccount pod-reader should not delete pods"

ok "module 07 verified"
