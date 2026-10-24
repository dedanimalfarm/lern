#!/usr/bin/env bash
# Самопроверка сертификации — для CI и автора задач. Доказывает, что:
#   1) карточка, задания, шаблон и эталон описывают одни и те же 40 задач;
#   2) пустой шаблон даёт 0 из 40, эталонные ответы — 40 из 40 и сертификат;
#   3) равносильные записи (tests/alternatives.txt) засчитываются;
#   4) типичные ошибки (tests/mistakes.txt) — FAIL в каждой из 40 задач;
#   5) ответы не по правилам (tests/rule-breakers.txt) — FAIL, даже с верным выводом;
#   6) check.sh ничего не меняет в арене, а повторный setup.sh не трогает арену и ответы.
#
# Арена и ответы создаются в новом каталоге mktemp -d; ~/ls-arena не используется.
# Скрипт ничего не удаляет — временный каталог остаётся, поэтому запускайте его
# в одноразовом контейнере (так делает CI) или удалите каталог сами.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

die() { echo "SELFTEST FAIL: $*"; exit 1; }

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

echo "== 1. 40 задач везде"
[ "$(grep -c '\[ \]' card.txt)" -eq 40 ] || die "в card.txt не 40 клеток"
[ "$(grep -cE '^[0-9]{2}  ' tasks.txt)" -eq 40 ] || die "в tasks.txt не 40 задач"
[ "$(grep -cE '^[0-9]{2}$' answers-template.txt)" -eq 40 ] || die "в answers-template.txt не 40 строк"
[ "$(numbers solutions/answers.txt | sort -u | wc -l)" -eq 40 ] || die "в solutions/answers.txt не 40 ответов"
[ "$(numbers tests/mistakes.txt | sort -u | wc -l)" -eq 40 ] || die "в tests/mistakes.txt не 40 ошибок"

before=$(fingerprint)

echo "== 2a. пустой шаблон → 0 из 40"
check_with "$LS_ANSWERS"
[ "$RC" -eq 1 ] || die "шаблон: код $RC, ожидался 1"
grep -q '^Итого: 0 из 40' <<<"$OUT" || die "шаблон: не 0 из 40"
[ "$(grep -c '^\[ -- \]' <<<"$OUT")" -eq 40 ] || die "шаблон: не у всех задач «нет ответа»"

echo "== 2b. эталон → 40 из 40 и сертификат"
check_with solutions/answers.txt
grep -A1 '^\[FAIL\]' <<<"$OUT" || true
[ "$RC" -eq 0 ] || die "эталон: код $RC, ожидался 0"
grep -q '^Итого: 40 из 40' <<<"$OUT" || die "эталон: не 40 из 40"
grep -q 'CERTIFICATE OF ACHIEVEMENT' <<<"$OUT" || die "эталон: нет сертификата"
grep -q '^Ранг: LORD OF THE LiSts' <<<"$OUT" || die "эталон: не высший ранг"
[ "$(grep -c '\[x\]' <<<"$OUT")" -eq 40 ] || die "эталон: в карточке не 40 отметок [x]"

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
grep -q '^Итого: 0 из 40' <<<"$OUT" || die "ошибки: не 0 из 40"

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
