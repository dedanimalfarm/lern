#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: наивный контейнер (только chroot, без
# pivot_root) — побег /proc/1/root выводит на ХОСТ. Контраст с mycontainer в fix.sh.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

A=/lab/10/alpine
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
if [[ ! -x "$A/bin/sh" ]]; then
  mkdir -p "$A"; curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$A" 2>/dev/null || { echo "не скачать alpine (нет интернета?)"; exit 1; }
fi
N=/lab/11-naive; rm -rf "$N"; cp -a "$A" "$N"
mount -t proc proc "$N/proc"

echo "hostname ХОСТА: $(hostname)"
# shellcheck disable=SC2016  # $(...) раскрывается во ВНУТРЕННЕМ sh chroot'а
chroot "$N" /bin/sh -c 'echo "внутри naive chroot hostname: $(hostname)"; echo "побег chroot /proc/1/root -> hostname: $(chroot /proc/1/root /bin/sh -c hostname 2>/dev/null || echo FAIL)"'

umount -l "$N/proc" 2>/dev/null || true
rm -rf "$N"
echo "разбор: broken/scenario-01/README.md · контраст: solutions/01-pivot-root/fix.sh"
