#!/usr/bin/env bash
# verify: ставим три лимита на листовые cgroup и доказываем срабатывание —
# CPU (throttling в cpu.stat), память (OOM-kill в memory.events), PIDs (EAGAIN
# на fork). Нагрузка переносимая, БЕЗ stress-ng: busy-loop / tail /dev/zero /
# fork-цикл. Контракт [OK]/[FAIL] поверх helpers.sh.
set -euo pipefail
# shellcheck disable=SC2016  # в sh -c '...' одинарные кавычки: $$ раскрывается во ВНУТРЕННЕМ shell
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
CG=/sys/fs/cgroup
[[ -f "$CG/cgroup.controllers" ]] || fail "cgroup v2 не примонтирована"
V="$CG/lpi-verify"
mkdir -p "$V"
echo '+cpu +memory +pids' > "$V/cgroup.subtree_control" 2>/dev/null || true

# ── CPU: cpu.max=10% одного ядра → throttling ──────────────────────────────
mkdir -p "$V/cpu"
echo "10000 100000" > "$V/cpu/cpu.max"
sh -c 'echo $$ > '"$V"'/cpu/cgroup.procs; exec timeout 3 bash -c "while :; do :; done"' >/dev/null 2>&1 || true
THR=$(awk '/^nr_throttled/{print $2}' "$V/cpu/cpu.stat" 2>/dev/null || true)
[[ "${THR:-0}" -ge 1 ]] || fail "CPU: throttling не сработал (nr_throttled=${THR:-0})"
ok "CPU: cpu.max=10% → throttling (nr_throttled=$THR)"

# ── Memory: memory.max=32M, без swap → OOM-kill ────────────────────────────
mkdir -p "$V/mem"
echo 32M > "$V/mem/memory.max"
echo 0   > "$V/mem/memory.swap.max" 2>/dev/null || true
# tail запускаем ДОЧЕРНИМ процессом сабшелла; завершающее ':' не даёт bash
# оптимизировать последнюю команду через exec (иначе tail СТАНОВИТСЯ сабшеллом
# и «Killed» печатает уже verify.sh). Так job-сообщение об OOM печатает сам
# сабшелл — а его stdout/stderr перенаправлены в /dev/null. Сабшелл выходит чисто.
( echo "$BASHPID" > "$V/mem/cgroup.procs"; tail /dev/zero; : ) >/dev/null 2>&1 || true
OOM=$(awk '/^oom_kill /{print $2}' "$V/mem/memory.events" 2>/dev/null || true)
[[ "${OOM:-0}" -ge 1 ]] || fail "MEM: OOM-kill не сработал (oom_kill=${OOM:-0})"
ok "MEM: memory.max=32M → OOM-kill (oom_kill=$OOM)"

# ── PIDs: pids.max=3 → лишние fork отклонены (EAGAIN) ──────────────────────
mkdir -p "$V/pids"
echo 3 > "$V/pids/pids.max"
ERR=$(sh -c 'echo $$ > '"$V"'/pids/cgroup.procs; for i in $(seq 1 10); do sleep 2 & done; wait' 2>&1 || true)
FAILS=$(printf '%s\n' "$ERR" | grep -c -iE 'cannot fork|Resource temporarily' || true)
[[ "${FAILS:-0}" -ge 1 ]] || fail "PIDS: лишние fork не заблокированы (совпадений=${FAILS:-0})"
ok "PIDS: pids.max=3 → fork отклонён (EAGAIN, совпадений: $FAILS)"

ok "module 04-cgroups-v2 verified"
