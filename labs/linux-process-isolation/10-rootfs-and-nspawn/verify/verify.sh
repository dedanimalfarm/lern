#!/usr/bin/env bash
# verify: запускаем alpine-rootfs через systemd-nspawn и доказываем изоляцию —
# (1) внутри это alpine, (2) PID 1 = sh (PID-ns), (3) hostname ≠ хостового (UTS-ns).
# Host-only: без systemd-nspawn (WSL2) — мягкий пропуск, прогон не валим.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
command -v systemd-nspawn >/dev/null 2>&1 \
  || { warn "нет systemd-nspawn — модуль host-only, проверка пропущена"; exit 0; }

A=/lab/10-nspawn/alpine
require_file "$A/etc/os-release" "alpine rootfs (запусти prepare.sh на хосте с интернетом)"

# Один запуск nspawn собирает все маркеры (меньше шанс на 'machine already exists').
# shellcheck disable=SC2016  # $(...) раскрывается во ВНУТРЕННЕМ sh контейнера, не здесь
OUT=$(systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c 'echo "ID=$(grep ^ID= /etc/os-release | cut -d= -f2)"; echo "PID1=$(p=$(cat /proc/1/comm); echo $p)"; echo "HOST=$(hostname)"' 2>/dev/null || true)

ID=$(printf '%s\n' "$OUT" | sed -n 's/^ID=//p' | tr -d '\r' || true)
[[ "$ID" == *alpine* ]] || fail "внутри nspawn не alpine (ID='$ID'). Вывод: $OUT"
ok "rootfs запущен через systemd-nspawn: ID=alpine"

P1=$(printf '%s\n' "$OUT" | sed -n 's/^PID1=//p' | tr -d '\r' || true)
[[ "$P1" == "sh" ]] || fail "PID 1 внутри != sh (получено '$P1'). Вывод: $OUT"
ok "PID-ns изолирован: PID 1 внутри = sh"

NSHN=$(printf '%s\n' "$OUT" | sed -n 's/^HOST=//p' | tr -d '\r' || true)
[[ -n "$NSHN" && "$NSHN" != "$(hostname)" ]] \
  || fail "hostname внутри nspawn не изолирован (внутри '$NSHN', host '$(hostname)')"
ok "UTS-ns изолирован: hostname внутри = '$NSHN' (host = '$(hostname)')"

ok "module 10-rootfs-and-nspawn verified"
