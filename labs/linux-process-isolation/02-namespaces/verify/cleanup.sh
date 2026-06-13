#!/usr/bin/env bash
# cleanup: у модуля 02 нет персистентных артефактов — все namespace умирают
# вместе с породившим их процессом unshare. Оставлен для единообразия контракта
# prepare/verify/cleanup (его всегда зовёт trap из run-module.sh).
set -uo pipefail
echo "[OK] cleanup 02-namespaces (нет персистентных артефактов)"
