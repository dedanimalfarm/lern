#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: systemd-nspawn на пустом каталоге (нет
# os-release / OS-дерева) → отказ "doesn't look like it has an OS tree. Refusing."
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v systemd-nspawn >/dev/null || { echo "нет systemd-nspawn — сценарий только на реальном хосте"; exit 0; }

D=/lab/10-broken
rm -rf "$D"; mkdir -p "$D/empty"
echo "nspawn на пустом каталоге (нет OS-дерева):"
systemd-nspawn -q -D "$D/empty" --pipe -- /bin/sh -c 'echo inside' 2>&1 | head -2

rm -rf "$D"
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-proper-rootfs/fix.sh"
