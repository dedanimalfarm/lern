#!/usr/bin/env bash
set -euo pipefail
kubectl -n team-x-dev patch hierarchyconfiguration hierarchy --type=merge -p '{"spec":{"parent":""}}' >/dev/null 2>&1 || true
kubectl delete ns team-x-dev team-x --ignore-not-found --timeout=120s
