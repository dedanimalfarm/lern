#!/usr/bin/env bash
# Самопроверка пробного экзамена — для CI и для автора задач.
# Запускать от root в ОДНОРАЗОВОМ контейнере или VM: скрипт выполняет setup.sh
# и меняет систему. Один стенд — один режим (setup.sh второй раз не запустится).
#
#   ./ci-selftest.sh            режим solutions (по умолчанию) доказывает, что:
#                               1) на нетронутом стенде verify.sh даёт 0 баллов и код 1;
#                               2) эталонные решения дают 100 из 100 и код 0.
#   ./ci-selftest.sh mistakes   доказывает, что ловушки работают: после типичных
#                               ошибок (tests/typical-mistakes.sh) каждая такая задача — FAIL.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
MODE=${1:-solutions}

die() { echo "SELFTEST FAIL: $*"; exit 1; }
run_verify() { set +e; OUT=$(./verify.sh); RC=$?; set -e; printf '%s\n' "$OUT"; }

./setup.sh

case "$MODE" in
  solutions)
    echo "== verify.sh на нетронутом стенде (ожидаем 0 баллов)"
    run_verify
    [ "$RC" -eq 1 ] || die "до решений verify.sh вернул $RC, ожидался 1"
    printf '%s\n' "$OUT" | grep -q '^Итого: 0 из 100' || die "до решений должно быть 0 баллов"

    echo "== эталонные решения"
    ./solutions/solve.sh

    echo "== verify.sh после решений (ожидаем 100 из 100)"
    run_verify
    [ "$RC" -eq 0 ] || die "после решений verify.sh вернул $RC, ожидался 0"
    printf '%s\n' "$OUT" | grep -q '^Итого: 100 из 100' || die "после решений должно быть 100 баллов"
    ;;
  mistakes)
    echo "== типичные ошибки"
    ./tests/typical-mistakes.sh

    echo "== verify.sh после ошибок (каждая задача с ошибкой — FAIL)"
    run_verify
    [ "$RC" -eq 1 ] || die "после ошибок verify.sh вернул $RC, ожидался 1"
    for n in 02 03 04 05 06 07 08 09 10 11 13 14 15 16 17 18; do
      printf '%s\n' "$OUT" | grep -q "^\[FAIL\] $n " || die "ошибка в задаче $n не поймана — ловушка не работает"
    done
    printf '%s\n' "$OUT" | grep -q '^\[ OK \] 12 ' || die "задача 12 решена верно, но не засчитана"
    ;;
  *) die "неизвестный режим: $MODE (solutions или mistakes)" ;;
esac

echo "SELFTEST OK ($MODE)"
