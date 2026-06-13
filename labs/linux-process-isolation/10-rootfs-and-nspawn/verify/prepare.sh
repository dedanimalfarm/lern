#!/usr/bin/env bash
# prepare: host-only. Без systemd-nspawn (WSL2) — мягкий пропуск. Иначе качаем
# alpine minirootfs (нужен интернет), который verify запустит через nspawn.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
command -v systemd-nspawn >/dev/null 2>&1 \
  || { warn "нет systemd-nspawn (WSL2/без systemd-container) — модуль host-only, проверка пропущена"; exit 0; }
need_bin curl
need_bin tar

A=/lab/10-nspawn/alpine
rm -rf /lab/10-nspawn
mkdir -p "$A"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$A" 2>/dev/null \
  || fail "не удалось скачать/распаковать alpine minirootfs (нет интернета на хосте?)"
[[ -x "$A/bin/sh" ]] || fail "alpine rootfs неполный (нет /bin/sh)"
ok "alpine minirootfs готов: $A"
