#!/usr/bin/env bash
# prepare: модулю 05 не нужны персистентные артефакты — только инструменты libcap.
# Все тестовые файлы создаёт и убирает verify.sh/cleanup.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin capsh
need_bin setcap
need_bin getcap
ok "libcap на месте (setcap/getcap/capsh)"
