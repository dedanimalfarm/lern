#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin kubectl
require_namespace lab

# CRD зарегистрирована
kubectl get crd webapps.lab.example.com >/dev/null 2>&1 \
  || fail "CRD webapps.lab.example.com not found"

# Экземпляр кастомного ресурса создан
require_resource lab webapp my-webapp
ok "CRD WebApp registered + my-webapp instance exists"

ok "module 19 verified"
