#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete pod crasher dnscheck tmp x --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
kubectl -n lab delete deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
