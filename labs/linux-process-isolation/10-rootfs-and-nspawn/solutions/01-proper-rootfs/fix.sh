#!/usr/bin/env bash
# Чинит инцидент scenario-01: даём настоящий rootfs (распаковка alpine minirootfs) —
# nspawn запускается.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v systemd-nspawn >/dev/null || { echo "нет systemd-nspawn — только на реальном хосте"; exit 0; }

A=/lab/10-fix/alpine
rm -rf /lab/10-fix; mkdir -p "$A"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
echo "распаковываем настоящий rootfs (alpine) и запускаем:"
curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$A" 2>/dev/null
# shellcheck disable=SC2016  # $(...) раскрывается во ВНУТРЕННЕМ sh контейнера
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c 'echo "  внутри: $(grep ^PRETTY_NAME= /etc/os-release)"'

rm -rf /lab/10-fix
