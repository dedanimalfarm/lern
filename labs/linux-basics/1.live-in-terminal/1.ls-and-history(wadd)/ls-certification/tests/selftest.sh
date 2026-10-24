#!/usr/bin/env bash
# Самопроверка сертификации — для CI и автора задач. Доказывает, что:
#   1) карточка, задания, шаблон и эталон описывают одни и те же N задач (N = TOTAL из check.sh);
#   2) пустой шаблон даёт 0 из N, эталонные ответы — N из N и сертификат;
#   3) равносильные записи (tests/alternatives.txt) засчитываются;
#   4) типичные ошибки (tests/mistakes.txt) — FAIL в каждой задаче;
#   5) ответы не по правилам (tests/rule-breakers.txt) — FAIL, даже с верным выводом;
#   6) check.sh ничего не меняет в арене, а повторный setup.sh не трогает арену и ответы.
#
# Арена и ответы создаются в новом каталоге mktemp -d; ~/ls-arena не используется.
# Скрипт ничего не удаляет — временный каталог остаётся, поэтому запускайте его
# в одноразовом контейнере (так делает CI) или удалите каталог сами.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

die() { echo "SELFTEST FAIL: $*"; exit 1; }

N=$(sed -n 's/^TOTAL=\([0-9]*\)$/\1/p' check.sh)
[ -n "$N" ] || die "в check.sh нет строки TOTAL=число"

WORK=$(mktemp -d)
export LS_ARENA="$WORK/arena" LS_ANSWERS="$WORK/answers.txt"
echo "== арена: $LS_ARENA"
./setup.sh >/dev/null

# Запуск check.sh с другим файлом ответов: OUT — вывод, RC — код возврата.
check_with() { set +e; OUT=$(LS_ANSWERS=$1 ./check.sh); RC=$?; set -e; }
# Номера задач из файла ответов (строки «NN команда»).
numbers() { grep -oE '^[0-9]{2}' "$1"; }
# Отпечаток арены: путь, тип, размер, права и mtime каждого файла.
fingerprint() { (cd "$LS_ARENA" && find . -printf '%p %y %s %m %T@\n' | LC_ALL=C sort | md5sum); }

echo "== 1. $N задач везде"
[ "$(grep -c '\[ \]' card.txt)" -eq "$N" ] || die "в card.txt не $N клеток"
[ "$(grep -cE '^[0-9]{2}  ' tasks.txt)" -eq "$N" ] || die "в tasks.txt не $N задач"
[ "$(grep -cE '^[0-9]{2}$' answers-template.txt)" -eq "$N" ] || die "в answers-template.txt не $N строк"
[ "$(numbers solutions/answers.txt | sort -u | wc -l)" -eq "$N" ] || die "в solutions/answers.txt не $N ответов"
[ "$(numbers tests/mistakes.txt | sort -u | wc -l)" -eq "$N" ] || die "в tests/mistakes.txt не $N ошибок"

before=$(fingerprint)

echo "== 2a. пустой шаблон → 0 из $N"
check_with "$LS_ANSWERS"
[ "$RC" -eq 1 ] || die "шаблон: код $RC, ожидался 1"
grep -q "^Итого: 0 из $N\$" <<<"$OUT" || die "шаблон: не 0 из $N"
[ "$(grep -c '^\[ -- \]' <<<"$OUT")" -eq "$N" ] || die "шаблон: не у всех задач «нет ответа»"

echo "== 2b. эталон → $N из $N и сертификат"
check_with solutions/answers.txt
grep -A1 '^\[FAIL\]' <<<"$OUT" || true
[ "$RC" -eq 0 ] || die "эталон: код $RC, ожидался 0"
grep -q "^Итого: $N из $N\$" <<<"$OUT" || die "эталон: не $N из $N"
grep -q 'CERTIFICATE OF ACHIEVEMENT' <<<"$OUT" || die "эталон: нет сертификата"
grep -q '^Ранг: THE LORD OF THE LiSt' <<<"$OUT" || die "эталон: не высший ранг"
[ "$(grep -c '\[x\]' <<<"$OUT")" -eq "$N" ] || die "эталон: в карточке не $N отметок [x]"

echo "== 3. равносильные записи → OK"
check_with tests/alternatives.txt
for n in $(numbers tests/alternatives.txt); do
  grep -q "^\[ OK \] $n " <<<"$OUT" || { grep -A1 "^\[FAIL\] $n " <<<"$OUT"; die "верный вариант задачи $n не засчитан"; }
done

echo "== 4. типичные ошибки → FAIL в каждой задаче"
check_with tests/mistakes.txt
[ "$RC" -eq 1 ] || die "ошибки: код $RC, ожидался 1"
for n in $(numbers tests/mistakes.txt); do
  grep -q "^\[FAIL\] $n " <<<"$OUT" || die "ошибка в задаче $n засчитана — задача её не ловит"
done
grep -q "^Итого: 0 из $N\$" <<<"$OUT" || die "ошибки: не 0 из $N"

echo "== 5. нарушения правил → FAIL"
check_with tests/rule-breakers.txt
for n in $(numbers tests/rule-breakers.txt); do
  grep -q "^\[FAIL\] $n " <<<"$OUT" || die "ответ не по правилам в задаче $n засчитан"
done

echo "== 6. check.sh не меняет арену, повторный setup.sh ничего не трогает"
[ "$(fingerprint)" = "$before" ] || die "после check.sh арена изменилась"
echo '01 ls' >"$LS_ANSWERS"
./setup.sh >/dev/null
[ "$(cat "$LS_ANSWERS")" = '01 ls' ] || die "повторный setup.sh перезаписал ответы"
[ "$(fingerprint)" = "$before" ] || die "повторный setup.sh изменил арену"

echo "SELFTEST OK (временный каталог $WORK оставлен)"
