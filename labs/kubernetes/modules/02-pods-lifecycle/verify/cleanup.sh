#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete pod bad-image phase-demo term-demo --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
kubectl -n lab delete deploy,svc,pod --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
