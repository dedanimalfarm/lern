#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Снять поломку и вернуть стенд к дефолту; HTTPS-стенд (если поднимали) гасим.
curl -s -X POST http://127.0.0.1:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d '{"mode":"none"}' >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/api.sh" tls-down >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/api.sh" up >/dev/null 2>&1 || true
echo "[OK] module 08 cleaned (fault=none, HTTPS-стенд погашен, стенд в дефолте)"
