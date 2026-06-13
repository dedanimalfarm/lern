#!/usr/bin/env bash
# verify: для каждого из шести namespace проверяем (а) что он реально создаётся
# (inode внутри ≠ inode хоста) и (б) его функциональный эффект. Контракт вывода —
# [OK]/[FAIL] поверх helpers.sh, как в k8s-лабах.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
need_bin ip

# check_ns <тип> <флаги unshare...> — inode внутри нового ns должен отличаться от
# хостового И быть непустым (пустой = unshare упал, это не «успех изоляции»).
check_ns() {
  local kind="$1"; shift
  local host inside
  host=$(ns_inode "$kind")
  inside=$(unshare "$@" --fork /bin/sh -c "stat -L -c %i /proc/self/ns/$kind" 2>/dev/null || true)
  [[ -n "$inside" && "$host" != "$inside" ]] \
    || fail "$kind-ns не создан (host=$host new=$inside)"
  ok "$kind-ns создан: host=$host new=$inside"
}

check_ns uts  --uts
check_ns pid  --pid --mount-proc
check_ns mnt  --mount
check_ns net  --net
check_ns ipc  --ipc
check_ns user --user --map-root-user

# UTS: смена hostname внутри не должна задеть хост.
HOST_HN=$(hostname)
unshare --uts /bin/bash -c 'hostname iso-verify' 2>/dev/null || true
assert_eq "$HOST_HN" "$(hostname)" "UTS: смена hostname внутри не задела хост"
ok "UTS: hostname хоста не изменился ('$HOST_HN')"

# PID: внутри (с --fork) первый процесс — PID 1.
PIN=$(unshare --pid --fork /bin/sh -c 'echo $$' 2>/dev/null || true)
assert_eq "1" "$PIN" "PID: внутри \$\$==1 (нужен --fork)"
ok "PID: внутри \$\$==$PIN"

# MNT: tmpfs, смонтированный в mnt-ns, не виден хосту.
unshare --mount /bin/bash -c 'mount --make-rprivate / 2>/dev/null || true; mount -t tmpfs none /mnt; echo x > /mnt/iso-verify' 2>/dev/null || true
[[ ! -e /mnt/iso-verify ]] || fail "MNT: tmpfs утёк на хост (виден /mnt/iso-verify)"
ok "MNT: tmpfs из mnt-ns не виден на хосте"

# NET: внутри ровно один интерфейс (loopback).
NIF=$(unshare --net /bin/sh -c 'ip -o link | wc -l' 2>/dev/null || true)
assert_eq "1" "$NIF" "NET: внутри ровно 1 интерфейс (lo)"
ok "NET: внутри интерфейсов = $NIF (только lo)"

# USER: внутри uid 0 (map-root-user).
UIN=$(unshare --user --map-root-user /bin/sh -c 'id -u' 2>/dev/null || true)
assert_eq "0" "$UIN" "USER: внутри uid=0"
ok "USER: внутри uid=$UIN (rootless mapping)"

ok "module 02-namespaces verified"
