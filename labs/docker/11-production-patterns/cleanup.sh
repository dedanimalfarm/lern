#!/usr/bin/env bash
set -euo pipefail

docker compose -f lab/compose.yaml down -v --remove-orphans >/dev/null 2>&1 || true
cp lab/proxy/blue.conf lab/proxy/default.conf 2>/dev/null || true
