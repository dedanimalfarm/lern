#!/usr/bin/env bash
# prepare: убеждаемся, что есть alpine rootfs (mycontainer берёт его из /lab/10/
# alpine) и сам mycontainer.sh. Скачиваем alpine при отсутствии (нужен интернет).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
need_bin mount
need_bin curl
require_file "$ROOT_DIR/11-capstone/mycontainer.sh" "mycontainer.sh"

A=/lab/10/alpine
if [[ ! -x "$A/bin/sh" ]]; then
  rm -rf /lab/10
  mkdir -p "$A"
  URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
  curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$A" 2>/dev/null \
    || fail "не удалось скачать alpine rootfs (нет интернета на хосте?)"
fi
ok "alpine rootfs готов; mycontainer.sh на месте"
