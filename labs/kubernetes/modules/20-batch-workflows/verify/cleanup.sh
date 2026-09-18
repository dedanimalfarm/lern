#!/usr/bin/env bash
set -euo pipefail

kubectl -n lab delete job,cronjob --all --ignore-not-found >/dev/null 2>&1 || true
echo "cleanup: готово"
