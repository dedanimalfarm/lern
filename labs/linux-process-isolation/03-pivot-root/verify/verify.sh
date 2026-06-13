#!/usr/bin/env bash
# verify: выполняем pivot_root внутри одного unshare и проверяем, что (а) корень
# сменился на минимальный, (б) UTS изолирован, (в) побег /proc/1/root закрыт.
#
# Тонкость: после pivot_root хостовый /tmp недостижим, поэтому изнутри ничего не
# записать на хост — результат печатаем маркерами в stdout, а собирает и проверяет
# его РОДИТЕЛЬ (он остаётся в исходном namespace). Контракт [OK]/[FAIL] — на
# стороне родителя, поверх helpers.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin unshare
need_bin busybox
install -d /lab/03-pivot-root/newroot

# shellcheck disable=SC2016  # переменные/$() в одинарных кавычках раскрываются во ВНУТРЕННЕМ bash
OUTPUT=$(unshare --mount --pid --uts --fork --mount-proc /bin/bash -c '
  set -e
  NEW=/lab/03-pivot-root/newroot
  mount --make-rprivate /
  mount -t tmpfs none "$NEW"
  install -d "$NEW"/{bin,etc,proc,dev,old_root}
  cp /bin/busybox "$NEW/bin/"
  for a in sh ls cat hostname chroot mount umount grep; do ln -sf busybox "$NEW/bin/$a"; done
  echo pivoted > "$NEW/etc/hostname"
  mount -t proc proc "$NEW/proc"
  /bin/busybox mknod "$NEW/dev/null" c 1 3 2>/dev/null || true
  cd "$NEW"
  pivot_root . old_root
  /bin/busybox umount -l /old_root
  export PATH=/bin
  hostname pivoted-test
  printf "hostname=%s\n" "$(hostname)"
  shopt -s nullglob; entries=(/*); joined=""
  for e in "${entries[@]}"; do joined="$joined${e##*/},"; done
  printf "root=%s\n" "$joined"
  EL=$(/bin/chroot /proc/1/root /bin/sh -c "ls /" 2>/dev/null || echo FAIL)
  if echo "$EL" | grep -qE "home|usr|var"; then printf "escape=ESCAPED\n"; else printf "escape=CONFINED\n"; fi
' 2>&1 || true)

# --- проверки на стороне родителя (каждая подстановка с || true, как требует CLAUDE.md) ---
ROOTLS=$(printf '%s\n' "$OUTPUT" | grep '^root=' | cut -d= -f2 || true)
[[ -n "$ROOTLS" && "$ROOTLS" != *home* && "$ROOTLS" != *usr* && "$ROOTLS" != *var* ]] \
  || fail "pivot_root не дал минимальный корень (root='$ROOTLS'). Полный вывод:
$OUTPUT"
ok "pivot_root выполнен, новый корень минимальный: $ROOTLS"

printf '%s\n' "$OUTPUT" | grep -q 'hostname=pivoted-test' \
  || fail "UTS не изолирован (нет hostname=pivoted-test). Вывод:
$OUTPUT"
ok "UTS изолирован: hostname=pivoted-test"

printf '%s\n' "$OUTPUT" | grep -q 'escape=CONFINED' \
  || fail "побег /proc/1/root НЕ закрыт (escape!=CONFINED). Вывод:
$OUTPUT"
ok "побег /proc/1/root закрыт после pivot_root (escape=CONFINED)"

ok "module 03-pivot-root verified"
