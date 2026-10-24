#!/usr/bin/env bash
# Проверка сертификации «The Lord of the LiSt»: 26 задач, одна задача — одна команда.
# Задачи повторяют карточку card.txt: каждая команда карточки — одна задача, в том же порядке.
#
# Как проверяется ответ. Команда из файла ответов и эталонная команда запускаются по очереди
# в одной и той же арене, и сравниваются их вывод (stdout вместе с stderr) и код возврата.
# Поэтому засчитывается любая равносильная запись: ls -lt logs, ls -l -t logs и
# ls logs --sort=time -l печатают одно и то же. Даты, владелец и размеры не мешают:
# у обеих команд они одинаковые.
#
# check.sh читает вывод через конвейер, а не с терминала. Там ls и так печатает по одному
# имени на строку, без цвета и кавычек. Поэтому, если по выводу правильный ответ не отличить
# от неправильного (ls и ls -1), задача дополнительно требует флаг — см. NEED.
#
# Скрипт ничего не меняет: ls, wc и head только читают арену.
#
#   ./check.sh          результат по задачам, ранг; когда решены все — сертификат
#   ./check.sh --card   то же плюс карточка с отметками [x] у решённых задач
#
#   LS_ARENA, LS_ANSWERS — как в setup.sh. LS_CERT_NAME — имя в сертификате.
# Код возврата: 0 — все задачи решены, 1 — не все, 2 — нет арены или файла ответов.
set -uo pipefail

HERE=$(dirname "$(readlink -f "$0")")
ARENA=${LS_ARENA:-$HOME/ls-arena}
ANSWERS=${LS_ANSWERS:-$HOME/ls-answers.txt}
CARD="$HERE/card.txt"
SHOW_CARD=0
[ "${1:-}" = "--card" ] && SHOW_CARD=1

[ -d "$ARENA" ] || { echo "Нет арены $ARENA — сначала запустите $HERE/setup.sh"; exit 2; }
[ -f "$ANSWERS" ] || { echo "Нет файла ответов $ANSWERS — его создаёт $HERE/setup.sh"; exit 2; }

# ---------------------------------------------------------------- задачи
# task НОМЕР ФОРМА 'ЭТАЛОН' ['NEED — обязательный фрагмент, regex' 'почему он нужен']
# ФОРМА: ls   — одна команда ls без конвейера;
#        pipe — ls и один | в wc, head или tail.
declare -A FORM REF NEED WHY
task() { FORM[$1]=$2; REF[$1]=$3; NEED[$1]=${4:-}; WHY[$1]=${5:-}; }

# Флаг внутри любой связки: -1, -l1, -1A и т. п.
flag() { printf '(^|[[:space:]])-[A-Za-z0-9]*%s' "$1"; }

# Уровни как на карточке. POWER COMBOS входят в LV5: звание The Lord of the LiSt —
# это все задачи карточки, и сертификат выдаётся вместе с ним.
LEVELS=(1:6:"LOOKER" 7:11:"DOT-FILE DETECTIVE" 12:15:"LONG-LIST LEGEND"
        16:21:"SORT SORCERER" 22:26:"THE LORD OF THE LiSt")
declare -A SUB=([24]="POWER COMBOS (входят в LV5)")
TOTAL=26

# LV1 · LOOKER
task  1 ls 'ls'
task  2 ls 'ls etc logs'
task  3 ls 'ls -1' "$(flag 1)|--format=single-column" \
  'вывод совпал: в конвейере ls и так пишет по имени в строке. В терминале будут колонки — нужен флаг'
task  4 ls 'ls etc/*.conf'
task  5 ls 'ls words/?a??'
task  6 ls 'ls words/[ab]*'
# LV2 · DOT-FILE DETECTIVE
task  7 ls 'ls -a'
task  8 ls 'ls -A'
task  9 ls 'ls -F'
task 10 ls 'ls -p'
task 11 ls 'ls -d */'
# LV3 · LONG-LIST LEGEND
task 12 ls 'ls -l'
task 13 ls 'ls -lh'
task 14 ls 'ls -li notes.txt hard.txt'
task 15 ls 'ls -R deep'
# LV4 · SORT SORCERER
task 16 ls 'ls -lt logs'
task 17 ls 'ls -ltr logs'
task 18 ls 'ls -lS logs'
task 19 ls 'ls -lSr logs'
task 20 ls 'ls -X docs'
task 21 ls 'ls -U logs' "$(flag U)|--sort=none" \
  'порядок в каталоге случайно совпал с алфавитом. Нужен флаг, который отключает сортировку'
# LV5 · THE LORD OF THE LiSt
task 22 ls 'ls -l current'
task 23 pipe 'ls -A | wc -l'
# POWER COMBOS
task 24 ls 'ls -lah'
task 25 ls 'ls -ld */'
task 26 pipe 'ls -lhS logs | head -5'

# ---------------------------------------------------------------- форма ответа
RE_ENV='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
RE_LS="${RE_ENV}(\\\\?ls|command[[:space:]]+ls)([[:space:]]|$)"
RE_TAIL='^[[:space:]]*(wc|head|tail)([[:space:]]|$)'
RE_SKIP='^[[:space:]]*(#|$)'
RE_ANS='^[[:space:]]*([0-9]{1,2})[.:)]?([[:space:]]+(.*))?$'

# Печатает, что не так с формой ответа, и возвращает 1; молчит и возвращает 0, если всё в порядке.
check_form() {
  local form=$1 cmd=$2 left right
  # Одинарные кавычки нарочно: ищем в ответе буквальные символы $( , а не подстановку.
  # shellcheck disable=SC2016
  case $cmd in
    *';'* | *'&'* | *'>'* | *'<'* | *'`'* | *'$('*)
      echo 'нужна одна команда: без ; && || > < и $(...)'; return 1 ;;
  esac
  left=${cmd%%|*}
  if [[ $cmd == *'|'* ]]; then
    [ "$form" = pipe ] || { echo 'в этой задаче конвейер | не нужен'; return 1; }
    right=${cmd#*|}
    [[ $right != *'|'* ]] || { echo 'здесь нужен ровно один |'; return 1; }
    [[ $right =~ $RE_TAIL ]] || { echo 'после | можно только wc, head или tail'; return 1; }
  fi
  [[ $left =~ $RE_LS ]] && return 0
  echo 'команда должна начинаться с ls'; return 1
}

# Запуск в арене чистым bash: без ~/.bashrc, значит без алиасов (ll, ls --color).
# OUT — вывод, где путь арены убран (ответ с ~/ls-arena/logs равен ответу с logs), RC — код.
run() {
  OUT=$(cd "$ARENA" && timeout 10 bash --norc --noprofile -c "$1" 2>&1 </dev/null)
  RC=$?
  OUT=${OUT//"$ARENA/"/}
}

cut70() { local s=$1; [ ${#s} -le 70 ] && printf '%s' "$s" || printf '%s…' "${s:0:69}"; }

# Первая строка, где выводы расходятся: так видно, что именно не так (порядок, колонка, лишняя строка).
first_diff() {
  local -a a b
  local i n
  mapfile -t a <<<"$1"
  mapfile -t b <<<"$2"
  n=${#a[@]}
  [ ${#b[@]} -gt "$n" ] && n=${#b[@]}
  for ((i = 0; i < n; i++)); do
    if [ "${a[i]-}" != "${b[i]-}" ]; then
      printf 'вывод другой, строка %d\n         ожидалось: %s\n         у вас:     %s' $((i + 1)) \
        "$(cut70 "${a[i]-(конец вывода)}")" "$(cut70 "${b[i]-(конец вывода)}")"
      return
    fi
  done
}

# ---------------------------------------------------------------- ответы
# Строка ответа: номер и команда — «07 ls -a», «7. ls -a», «07: ls -a».
# Пустые строки и строки, начинающиеся с #, пропускаются. Если номер встречается дважды,
# действует последний ответ, но пустая строка из шаблона («07») ответ не стирает.
declare -A ANS
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  [[ $line =~ $RE_SKIP ]] && continue
  if [[ $line =~ $RE_ANS ]]; then
    k=$((10#${BASH_REMATCH[1]}))
    cmd=${BASH_REMATCH[3]}
    cmd=${cmd%"${cmd##*[![:space:]]}"}
    if [ -n "$cmd" ] || [ -z "${ANS[$k]+set}" ]; then
      ANS[$k]=$cmd
    fi
  fi
done <"$ANSWERS"

# ---------------------------------------------------------------- проверка
PASSED=0
MARKS=''
lvl=0
for ((n = 1; n <= TOTAL; n++)); do
  IFS=: read -r from _ name <<<"${LEVELS[lvl]}"
  if [ "$n" -eq "$from" ]; then
    printf '\n── LV%d · %s\n' $((lvl + 1)) "$name"
  fi
  [ -n "${SUB[$n]-}" ] && printf '\n── %s\n' "${SUB[$n]}"
  IFS=: read -r _ to _ <<<"${LEVELS[lvl]}"
  [ "$n" -eq "$to" ] && lvl=$((lvl + 1))

  cmd=${ANS[$n]-}
  num=$(printf '%02d' "$n")
  if [ -z "$cmd" ]; then
    printf '[ -- ] %s  нет ответа\n' "$num"
    MARKS+='0'
    continue
  fi
  if ! why=$(check_form "${FORM[$n]}" "$cmd"); then
    printf '[FAIL] %s  %s\n       %s\n' "$num" "$cmd" "$why"
    MARKS+='0'
    continue
  fi
  run "${REF[$n]}"; ref_out=$OUT; ref_rc=$RC
  run "$cmd"; got_out=$OUT; got_rc=$RC
  if [ "$got_out" != "$ref_out" ]; then
    printf '[FAIL] %s  %s\n       %s\n' "$num" "$cmd" "$(first_diff "$ref_out" "$got_out")"
    MARKS+='0'
  elif [ "$got_rc" != "$ref_rc" ]; then
    printf '[FAIL] %s  %s\n       код возврата %s, ожидался %s\n' "$num" "$cmd" "$got_rc" "$ref_rc"
    MARKS+='0'
  elif [ -n "${NEED[$n]}" ] && ! [[ $cmd =~ ${NEED[$n]} ]]; then
    printf '[FAIL] %s  %s\n       %s\n' "$num" "$cmd" "${WHY[$n]}"
    MARKS+='0'
  else
    printf '[ OK ] %s  %s\n' "$num" "$cmd"
    MARKS+='1'
    PASSED=$((PASSED + 1))
  fi
done

# ---------------------------------------------------------------- ранги
# Ранг — последний уровень, до которого все уровни закрыты целиком.
echo
RANK=''
open=1
for i in "${!LEVELS[@]}"; do
  IFS=: read -r from to name <<<"${LEVELS[i]}"
  len=$((to - from + 1))
  got=${MARKS:from-1:len}
  got=${got//0/}
  if [ ${#got} -eq "$len" ]; then
    mark='✔'
    [ "$open" -eq 1 ] && RANK=$name
  else
    mark=''
    open=0
  fi
  printf 'LV%d %-20s %2d/%-2d %s\n' $((i + 1)) "$name" ${#got} "$len" "$mark"
done
echo
printf 'Итого: %d из %d\n' "$PASSED" "$TOTAL"
if [ -n "$RANK" ]; then
  echo "Ранг: $RANK"
else
  echo 'Ранг: пока нет — закройте все задачи LV1'
fi

# ---------------------------------------------------------------- карточка и сертификат
boxes=$(grep -c '\[ \]' "$CARD")
[ "$boxes" -eq "$TOTAL" ] || echo "Внимание: в card.txt $boxes клеток, а задач $TOTAL — карточка не совпадает с заданиями."

# Клетки карточки идут в том же порядке, что и задачи: N-я клетка [ ] — задача N.
ticked_card() {
  awk -v marks="$MARKS" -v who="$1" '
    /\[ \]/ { n++; if (substr(marks, n, 1) == "1") sub(/\[ \]/, "[x]") }
    who != "" && /Awarded to:/ { $0 = "  Awarded to: " who }
    { print }' "$CARD"
}

# Строка по центру рамки шириной 70. Длину считаем в символах UTF-8, а не в байтах:
# иначе имя кириллицей (LS_CERT_NAME) сдвинуло бы правую границу рамки.
centre() {
  local LC_ALL=C.UTF-8 s=$1 w=70 l
  l=$(((w - ${#s}) / 2))
  printf '║%*s%s%*s║\n' "$l" '' "$s" $((w - l - ${#s})) ''
}

if [ "$PASSED" -eq "$TOTAL" ]; then
  who="${LS_CERT_NAME:-$(id -un)} · $(date +%F) · verified by check.sh"
  echo
  echo '╔══════════════════════════════════════════════════════════════════════╗'
  centre 'CERTIFICATE OF ACHIEVEMENT'
  centre 'THE LORD OF THE  L i S t'
  centre "awarded to ${LS_CERT_NAME:-$(id -un)}"
  centre "$TOTAL of $TOTAL tasks · one task, one command · $(date +%F)"
  echo '╚══════════════════════════════════════════════════════════════════════╝'
  echo
  ticked_card "$who"
elif [ "$SHOW_CARD" -eq 1 ]; then
  echo
  ticked_card ''
fi

[ "$PASSED" -eq "$TOTAL" ]
