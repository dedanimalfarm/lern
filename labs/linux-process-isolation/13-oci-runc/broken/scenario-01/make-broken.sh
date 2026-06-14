#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: дефолтный config.json (terminal=true) +
# runc run без интерактивного tty → "open /dev/tty: no such device or address".
# rootfs — alpine (static /bin/sh), чтобы дело было именно в terminal, не в rootfs.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
for t in runc python3 tar; do command -v "$t" >/dev/null || { echo "нет $t"; exit 1; }; done

B=/lab/13-broken/bundle
A=/lab/10/alpine
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
rm -rf /lab/13-broken; mkdir -p "$B/rootfs"
if [[ -x "$A/bin/sh" ]]; then cp -a "$A/." "$B/rootfs/"; else curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$B/rootfs" 2>/dev/null; fi
( cd "$B" && runc spec )   # terminal=true по умолчанию

echo "config process.terminal = $(python3 -c "import json;print(json.load(open('$B/config.json'))['process']['terminal'])")"
echo "runc run (terminal=true, без tty):"
( cd "$B" && runc run brk ) 2>&1 | head -2

runc delete --force brk 2>/dev/null || true
rm -rf /lab/13-broken
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-terminal-false/fix.sh"
