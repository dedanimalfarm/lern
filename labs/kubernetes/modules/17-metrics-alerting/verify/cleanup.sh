#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete servicemonitor,prometheusrule,deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
