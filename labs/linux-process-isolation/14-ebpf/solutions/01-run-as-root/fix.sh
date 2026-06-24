#!/usr/bin/env bash
# Чинит инцидент scenario-01: запуск bpftrace от root (есть CAP_BPF/CAP_SYS_ADMIN).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v bpftrace >/dev/null || { echo "нет bpftrace — только на хосте с eBPF"; exit 0; }

echo "bpftrace от root:"
bpftrace -e 'BEGIN { printf("ebpf ok\n"); exit(); }' 2>&1 | grep -E 'ebpf ok' | head -1
