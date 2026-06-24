#!/usr/bin/env bash
# cleanup: гасим фоновый reader и убираем временный файл. eBPF-программы bpftrace
# отцепляются при выходе процесса bpftrace сами.
set -uo pipefail
pkill -f 'lpi-ebpf-secret' 2>/dev/null || true
rm -f /tmp/lpi-ebpf-secret.txt /tmp/secret.txt 2>/dev/null || true
echo "[OK] cleanup 14-ebpf"
