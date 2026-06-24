#!/usr/bin/env bash
# verify: bpftrace перехватывает openat известного файла, который читает фоновый
# процесс — проверяем, что eBPF реально видит syscalls (как IDS). Host-only: без
# bpftrace (WSL2) — мягкий пропуск.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
command -v bpftrace >/dev/null 2>&1 \
  || { warn "нет bpftrace — модуль host-only, проверка пропущена"; exit 0; }

S=/tmp/lpi-ebpf-secret.txt
echo secret > "$S"
# фоновый «контейнер» открывает файл в цикле
( while :; do cat "$S" >/dev/null 2>&1; sleep 0.1; done ) &
RPID=$!

# трассируем openat 5с, считаем попадания по нашему файлу
N=$(timeout 8 stdbuf -oL bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("OPEN %s\n", str(args->filename)); }' 2>/dev/null \
      | grep -c 'lpi-ebpf-secret' || true)

kill -9 "$RPID" 2>/dev/null || true
pkill -f 'lpi-ebpf-secret' 2>/dev/null || true
rm -f "$S"

[[ "${N:-0}" -ge 1 ]] \
  || fail "bpftrace не перехватил openat файла $S (совпадений=$N) — работают ли bpftrace/BTF?"
ok "eBPF: bpftrace перехватил openat файла $S ($N раз)"

ok "module 14-ebpf verified"
