#!/usr/bin/env bash
# prepare: host-only. Без bpftrace (WSL2/без eBPF-tooling) — мягкий пропуск.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
command -v bpftrace >/dev/null 2>&1 \
  || { warn "нет bpftrace (WSL2/без eBPF-tooling) — модуль host-only, проверка пропущена"; exit 0; }
if [[ -r /sys/kernel/btf/vmlinux ]]; then BTF="есть"; else BTF="нет (нужны linux-headers)"; fi
ok "bpftrace на месте (BTF: $BTF)"
