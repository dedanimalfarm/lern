#!/usr/bin/env bash
# Прогон одного модуля по QA-контракту лабы (host-bash аналог k8s
# scripts/qa/run-module.sh):
#
#   verify/prepare.sh  →  verify/verify.sh  →  (trap EXIT) verify/cleanup.sh
#
# cleanup вынесен в trap, чтобы отрабатывать ВСЕГДА — в т.ч. при падении
# verify или SIGTERM/Ctrl-C, иначе остаются примонтированные /proc,/sys,/dev
# и rootfs в /lab. Модули старого формата (есть check.sh, нет verify/) идут
# через фолбэк на check.sh — это держит run-all.sh зелёным во время раскатки.
set -uo pipefail

TARGET="${1:-}"
[[ -n "$TARGET" ]] || { echo "usage: $0 <NN-stage>"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT_DIR/$TARGET"
[[ -d "$DIR" ]] || { echo "нет каталога модуля: $DIR"; exit 1; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[FAIL] нужен root: sudo $0 $TARGET" >&2
  exit 1
fi

CLEANED=0
# shellcheck disable=SC2317  # вызывается через trap, shellcheck этого не видит
do_cleanup() {
  [[ "$CLEANED" == 1 ]] && return 0
  CLEANED=1
  if [[ -x "$DIR/verify/cleanup.sh" ]]; then
    bash "$DIR/verify/cleanup.sh" || true
  fi
}
trap do_cleanup EXIT
# SIGTERM (от внешнего timeout) / Ctrl-C → выход с 124, что триггерит trap EXIT.
trap 'exit 124' TERM INT

echo "--- module: $TARGET ---"

if [[ -f "$DIR/verify/verify.sh" ]]; then
  if [[ -f "$DIR/verify/prepare.sh" ]]; then
    echo "prepare..."
    bash "$DIR/verify/prepare.sh" || { echo "[FAIL] prepare.sh упал"; exit 1; }
  fi
  echo "verify..."
  bash "$DIR/verify/verify.sh"
  exit $?
elif [[ -x "$DIR/check.sh" ]]; then
  echo "(legacy) check.sh..."
  bash "$DIR/check.sh"
  exit $?
else
  echo "[FAIL] у модуля нет ни verify/verify.sh, ни check.sh"
  exit 1
fi
