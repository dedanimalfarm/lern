#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete deploy,pod --all --ignore-not-found >/dev/null 2>&1 || true
kubectl -n lab delete rolebinding,role,sa,cm,secret --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
