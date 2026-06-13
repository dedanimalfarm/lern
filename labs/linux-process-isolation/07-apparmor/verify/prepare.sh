#!/usr/bin/env bash
# prepare: host-only модуль. Если AppArmor не активен в ядре (WSL2/контейнер) —
# мягко выходим (verify тоже пропустит). Иначе проверяем apparmor_parser.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
if [[ ! -d /sys/kernel/security/apparmor ]]; then
  warn "AppArmor не активен в ядре — модуль host-only (verify пропустит проверку)"
  exit 0
fi
need_bin apparmor_parser
ok "AppArmor активен; apparmor_parser на месте"
