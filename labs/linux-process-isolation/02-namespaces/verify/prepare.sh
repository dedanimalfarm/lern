#!/usr/bin/env bash
# prepare: у модуля 02 нет персистентных артефактов — namespace эфемерны и живут
# только на время каждой команды unshare. Поэтому prepare лишь подтверждает
# наличие инструментов (аналог проверки пререквизитов в k8s prepare.sh).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
need_bin ip
need_bin nsenter
ok "namespaces: инструменты на месте (unshare/ip/nsenter)"
