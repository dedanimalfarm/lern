#!/usr/bin/env bash
# Проверяет готовность хоста к курсу. Делит проверки на ДВА класса:
#   • CORE — обязательны для основного трека (модули 01-09, 13). Идут через
#     assert и считаются в summary: красное здесь = курс не пойдёт.
#   • Per-module — нужны лишь отдельным продвинутым модулям (07/10/12/14 и
#     нагрузочные тесты 04). Идут через info и в summary НЕ считаются: их
#     отсутствие (типично на WSL2) не должно «заваливать» весь сетап — просто
#     пропусти соответствующий модуль на этом хосте.
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/../scripts/lib.sh"

log "ядро и базовые возможности (CORE)"
KVER=$(uname -r); KMAJ=${KVER%%.*}; KMIN=$(echo "$KVER" | cut -d. -f2)
note "kernel: $KVER"
if (( KMAJ > 5 )) || { (( KMAJ == 5 )) && (( KMIN >= 10 )); }; then
  assert "kernel >= 5.10" true
else
  assert "kernel >= 5.10" false
fi
assert "cgroups v2 (unified hierarchy)" \
  bash -c 'mount | grep -q "cgroup2 on /sys/fs/cgroup"'
assert "/proc/self/ns/* есть (namespaces поддерживаются)" \
  test -e /proc/self/ns/uts
# Функциональная проверка вместо устаревшего sysctl kernel.unprivileged_userns_clone
# (на современных ядрах его нет): просто пробуем создать user-ns.
assert "user namespaces работают" \
  unshare --user --map-root-user true

log "инструменты CORE (модули 01-09, 13)"
for t in unshare nsenter ip chroot busybox runc mount stat; do
  assert "найден: $t" command -v "$t"
done

log "инструменты под отдельные модули (info — НЕ влияют на summary)"
info "setcap/getcap — модуль 05 (capabilities)" command -v setcap
info "capsh — модуль 05"                         command -v capsh
info "strace — модуль 06 (seccomp)"              command -v strace
info "AppArmor в ядре — модуль 07"               test -d /sys/kernel/security/apparmor
info "apparmor_parser — модуль 07"               command -v apparmor_parser
info "systemd-nspawn — модуль 10"                command -v systemd-nspawn
info "debootstrap — модуль 10"                   command -v debootstrap
info "newuidmap (uidmap) — модуль 12 (rootless)" command -v newuidmap
info "bpftrace — модуль 14 (ebpf)"               command -v bpftrace
info "stress-ng — модуль 04 (нагрузка CPU/RAM)"  command -v stress-ng
info "fio — модуль 04 (blkio)"                    command -v fio

log "опционально"
info "Docker (для сравнения с ручной сборкой)" command -v docker

summary
