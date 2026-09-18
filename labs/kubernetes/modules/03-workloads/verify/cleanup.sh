#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete pod dns --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
kubectl -n lab delete job,cronjob,ds,sts,deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true
kubectl -n lab delete pvc --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
