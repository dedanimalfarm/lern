#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: bpftrace от не-root → отказ
# "only supports running as the root user" (нужен CAP_BPF/CAP_SYS_ADMIN).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v bpftrace >/dev/null || { echo "нет bpftrace — сценарий только на хосте с eBPF"; exit 0; }

echo "bpftrace от nobody (не-root):"
su -s /bin/sh nobody -c 'bpftrace -e "BEGIN { exit(); }"' 2>&1 | head -2
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-run-as-root/fix.sh"
