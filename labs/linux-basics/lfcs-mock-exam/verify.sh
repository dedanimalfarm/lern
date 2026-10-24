#!/usr/bin/env bash
# Проверка пробного экзамена: 18 задач, 100 баллов, порог 67.
#
# Только читает состояние системы — ничего не создаёт и не меняет, поэтому
# запускать можно сколько угодно раз. Запуск: sudo ./verify.sh
# Код возврата: 0 — порог пройден, 1 — не пройден, 2 — ошибка запуска.
#
# Каждая задача проверяется целиком: баллы начисляются, только если выполнены
# все её условия; при неудаче выводится первое невыполненное условие.
#
# Функции tNN вызываются косвенно (check ... tNN), shellcheck этого не видит:
# shellcheck disable=SC2317
set -u

EXAM=/opt/exam
ANS=$EXAM/answers
PASS=67

[ "$(id -u)" -eq 0 ] || { echo "Запустите от root: sudo $0"; exit 2; }
[ -f "$EXAM/.started" ] || { echo "Стенд не подготовлен: сначала sudo ./setup.sh"; exit 2; }

# Каждая проверка tNN выполняется в подоболочке $(...) внутри check, поэтому exit
# завершает только её — на ПЕРВОМ невыполненном условии. (С return 1 функция
# продолжила бы работу, и успешная последняя проверка «перекрыла» бы провал.)
fail() { echo "$*"; exit 1; }
# Сжать пробелы и табуляции до одного пробела, убрать их по краям строк.
norm() { tr -s ' \t' '  ' | sed 's/^ //; s/ $//'; }
# Файл ответа существует и не пуст.
need() { [ -s "$1" ] || fail "нет файла $1 или он пустой"; }
# Выполнить команду в login-оболочке пользователя (читает /etc/profile.d и ~/.profile).
as_login() { local u=$1; shift; su - "$u" -c "$*" 2>/dev/null; }

# ---------------------------------------------------------------- задачи

t01() { need "$ANS/01.txt" || return 1
  [ "$(norm < "$ANS/01.txt" | xargs -n1 basename 2>/dev/null)" = "chage" ] || fail "ожидалось имя команды chage"; }

t02() { need "$ANS/02.txt" || return 1; need "$ANS/02-disk.txt" || return 1
  local want; want=$(grep -c '\[ERROR\]' "$EXAM/logs/app.log")
  [ "$(norm < "$ANS/02.txt")" = "$want" ] || fail "02.txt: неверное число строк ERROR"
  diff -q <(grep '\[ERROR\]' "$EXAM/logs/app.log" | grep -i disk) "$ANS/02-disk.txt" >/dev/null \
    || fail "02-disk.txt: должны быть ровно строки уровня ERROR со словом disk в любом регистре, в исходном порядке"; }

t03() { need "$ANS/03.out" || return 1; need "$ANS/03.err" || return 1
  diff -q <(printf 'report: start\nreport: 42 records\nreport: done\n') "$ANS/03.out" >/dev/null || fail "03.out: в нём должен быть только stdout"
  diff -q <(printf 'warning: cache is stale\nerror: 1 record skipped\n') "$ANS/03.err" >/dev/null || fail "03.err: в нём должен быть только stderr"; }

t04() { need "$ANS/04.txt" || return 1
  diff -q <(printf '%s\n' "$EXAM/data/cache/sub/big3.bin" "$EXAM/data/media/big1.bin") \
          <(norm < "$ANS/04.txt" | grep -v '^$' | sort) >/dev/null \
    || fail "04.txt: ожидались полные пути ровно двух файлов (больше 1 МиБ и владелец webuser)"; }

t05() { local B=$EXAM/backup/etc f
  for f in top.conf app/app.conf db/db.conf web/nginx/site.conf; do
    [ -f "$B/$f" ] || fail "нет $B/$f" || return 1
    cmp -s "$EXAM/etc/$f" "$B/$f" || fail "$B/$f отличается от оригинала" || return 1
  done
  [ "$(find "$B" -type f | wc -l)" -eq 4 ] || fail "в $B должны быть только 4 файла *.conf"; }

t06() { local f
  for f in old1.tmp old2.log; do
    [ -f "$EXAM/archive/old/$f" ] || fail "$f должен лежать в $EXAM/archive/old" || return 1
    [ ! -e "$EXAM/tmp/$f" ] || fail "$f остался в $EXAM/tmp" || return 1
  done
  for f in edge.tmp new1.tmp new2.log; do
    [ -f "$EXAM/tmp/$f" ] || fail "$f не старше 7 дней и должен остаться в $EXAM/tmp" || return 1
  done
  [ "$(find "$EXAM/archive/old" -type f | wc -l)" -eq 2 ] || fail "в $EXAM/archive/old лишние файлы"
  [ "$(find "$EXAM/archive/old/old2.log" -mtime +20 | wc -l)" -eq 1 ] || fail "время изменения файлов не должно было измениться"; }

t07() { diff -q <(printf '%s\n' '# Application settings' 'listen = 0.0.0.0:8080' 'max_connections = 200' \
                   'debug = false' 'log_level = info' '# debug = true is not allowed in production') \
          "$EXAM/config/app.conf" >/dev/null \
    || fail "app.conf отличается от ожидаемого (комментарий в последней строке менять нельзя)"; }

t08() { need "$ANS/08.txt" || return 1
  diff -q <(printf 'galina 7000\nnikita 6500\ndenis 6100\n') <(norm < "$ANS/08.txt" | grep -v '^$') >/dev/null \
    || fail "08.txt: ожидались 3 строки «имя зарплата» отдела IT (не ITOps) по убыванию зарплаты"; }

t09() { need "$ANS/09.txt" || return 1
  diff -q <(awk '{print $1}' "$EXAM/logs/access.log" | sort | uniq -c | sort -rn | head -5 | norm) \
          <(norm < "$ANS/09.txt" | grep -v '^$') >/dev/null \
    || fail "09.txt: ожидались 5 строк «количество IP» по убыванию"; }

t10() { local A=$EXAM/backup/project.tar.gz list
  [ -f "$A" ] || fail "нет $A" || return 1
  list=$(tar -tzf "$A" 2>/dev/null) || fail "$A не читается как tar.gz" || return 1
  list=$(printf '%s\n' "$list" | sed 's|^\./||; s|/$||' | sort)
  for f in project/README.md project/config.yml project/src/main.c project/src/util.c; do
    printf '%s\n' "$list" | grep -qx "$f" || fail "в архиве нет $f" || return 1
  done
  ! printf '%s\n' "$list" | grep -Eq '(^|/)logs(/|$)|\.tmp$' || fail "в архиве не должно быть logs/ и *.tmp"
  ! printf '%s\n' "$list" | grep -vq '^project\(/\|$\)' || fail "все пути в архиве должны начинаться с project/"; }

t11() { local R=$EXAM/restore F=$EXAM/restore/site/conf/nginx.conf
  [ -f "$F" ] || fail "нет $F" || return 1
  cmp -s "$F" <(tar -xJOf "$EXAM/archive/site.tar.xz" site/conf/nginx.conf) || fail "$F не совпадает с версией из архива" || return 1
  [ "$(find "$R" -type f | wc -l)" -eq 1 ] || fail "в $R должен быть только nginx.conf"; }

t12() { local pw
  [ "$(getent group devops | cut -d: -f3)" = "2050" ] || fail "нет группы devops с GID 2050" || return 1
  pw=$(getent passwd deploy) || fail "нет пользователя deploy" || return 1
  [ "$(echo "$pw" | cut -d: -f6)" = "/home/deploy" ] || fail "домашний каталог deploy — не /home/deploy" || return 1
  [ "$(echo "$pw" | cut -d: -f7)" = "/bin/bash" ] || fail "оболочка deploy — не /bin/bash" || return 1
  [ "$(stat -c %U /home/deploy 2>/dev/null)" = "deploy" ] || fail "каталог /home/deploy не создан или принадлежит не deploy" || return 1
  id -nG deploy | tr ' ' '\n' | grep -qx devops || fail "deploy не входит в группу devops" || return 1
  [ "$(getent shadow deploy | cut -d: -f8)" = "$(( $(date -ud 2030-12-31 +%s) / 86400 ))" ] || fail "срок действия учётной записи deploy — не 2030-12-31"; }

t13() { local rules
  visudo -cq >/dev/null 2>&1 || fail "visudo -c сообщает об ошибке в sudoers (синтаксис или права файлов)" || return 1
  rules=$(sudo -l -U deploy 2>/dev/null | sed -n '/may run the following commands/,$p' | tail -n +2)
  printf '%s\n' "$rules" | grep -Eq 'NOPASSWD: *(/usr)?/bin/journalctl$' || fail "deploy не может без пароля запускать /usr/bin/journalctl" || return 1
  ! printf '%s\n' "$rules" | grep -Eq '(^|[ ,:])ALL$' || fail "deploy разрешено больше, чем journalctl"; }

t14() { [ "$(stat -c '%a %U %G' /srv/devops 2>/dev/null)" = "2770 root devops" ] \
    || fail "/srv/devops: ожидались владелец root, группа devops, права 2770 (SGID + rwx для владельца и группы)"; }

t15() { local F=$EXAM/secure/report.txt
  runuser -u auditor -- cat "$F" >/dev/null 2>&1 || fail "auditor не может прочитать $F" || return 1
  ! runuser -u auditor -- test -w "$F" || fail "auditor не должен иметь права записи" || return 1
  ! runuser -u guest -- cat "$F" >/dev/null 2>&1 || fail "guest не должен читать $F" || return 1
  [ "$(stat -c '%a %U %G' "$F")" = "640 root root" ] || fail "права и владелец $F должны остаться 640 root:root — используйте ACL" || return 1
  [ "$(stat -c '%a %U %G' "$EXAM/secure")" = "750 root root" ] || fail "права каталога secure должны остаться 750 root:root — используйте ACL"; }

t16() { [ -L "$EXAM/current" ] || fail "$EXAM/current должен быть символической ссылкой" || return 1
  [ "$(readlink -f "$EXAM/current")" = "$EXAM/releases/v2" ] || fail "current указывает не на releases/v2" || return 1
  [ ! -e "$EXAM/releases/v1/v2" ] || fail "внутри releases/v1 появилась лишняя ссылка v2 (ln -sf без -n)" || return 1
  [ ! -L "$EXAM/data/docs/hard.txt" ] && [ -f "$EXAM/data/docs/hard.txt" ] || fail "нет обычного файла $EXAM/data/docs/hard.txt" || return 1
  [ "$(stat -c '%d:%i' "$EXAM/data/docs/hard.txt")" = "$(stat -c '%d:%i' "$EXAM/data/docs/master.txt")" ] \
    || fail "hard.txt — не жёсткая ссылка на master.txt (разные inode)"; }

t17() { id deploy >/dev/null 2>&1 || fail "нет пользователя deploy (задача 12)" || return 1
  [ "$(as_login auditor 'printenv EXAM_ENV')" = "lfcs" ] || fail "у auditor при входе нет EXAM_ENV=lfcs" || return 1
  [ "$(as_login guest 'printenv EXAM_ENV')" = "lfcs" ] || fail "у guest при входе нет EXAM_ENV=lfcs" || return 1
  [ "$(as_login deploy 'printenv APP_HOME')" = "/opt/app" ] || fail "у deploy при входе нет APP_HOME=/opt/app" || return 1
  [ -z "$(as_login auditor 'printenv APP_HOME')" ] || fail "APP_HOME должна быть только у deploy"; }

t18() { id deploy >/dev/null 2>&1 || fail "нет пользователя deploy (задача 12)" || return 1
  # bash -ic внутри login-оболочки: засчитывается umask и из ~/.profile, и из ~/.bashrc
  [ "$(as_login deploy 'bash -ic umask' | tail -n 1)" = "0027" ] || fail "umask deploy при входе — не 0027" || return 1
  [ "$(as_login auditor 'bash -ic umask' | tail -n 1)" != "0027" ] || fail "umask 0027 должен быть только у deploy"; }

# ---------------------------------------------------------------- подсчёт

total=0; got=0
check() { # номер баллы название функция
  local reason
  total=$((total + $2))
  if reason=$($4 2>&1); then
    got=$((got + $2)); printf '[ OK ] %s %2d б.  %s\n' "$1" "$2" "$3"
  else
    printf '[FAIL] %s %2d б.  %s — %s\n' "$1" "$2" "$3" "${reason:-не выполнено}"
  fi
}

check 01 3 "справка: команда срока действия пароля"      t01
check 02 5 "grep: строки ERROR и disk"                    t02
check 03 5 "перенаправление stdout и stderr"              t03
check 04 6 "find: размер и владелец"                      t04
check 05 6 "копирование *.conf со структурой"             t05
check 06 6 "перенос старых файлов"                        t06
check 07 7 "sed: правка конфига"                          t07
check 08 6 "awk/sort: топ зарплат IT"                     t08
check 09 5 "sort/uniq: топ IP"                            t09
check 10 6 "tar: архив с исключениями"                    t10
check 11 5 "tar: извлечь один файл"                       t11
check 12 7 "пользователь и группа"                        t12
check 13 6 "sudo: одна команда без пароля"                t13
check 14 5 "общий каталог с SGID"                         t14
check 15 7 "ACL: чтение для auditor"                      t15
check 16 5 "ссылки: current и hard.txt"                   t16
check 17 5 "переменные окружения при входе"               t17
check 18 5 "umask пользователя"                           t18

elapsed=$(( $(date +%s) - $(cat "$EXAM/.started") ))
echo
printf 'Итого: %d из %d (порог %d). Прошло времени: %d ч %02d мин\n' "$got" "$total" "$PASS" $((elapsed / 3600)) $((elapsed % 3600 / 60))
[ "$elapsed" -le 7200 ] || echo "Внимание: больше 2 часов — на настоящем экзамене время бы уже вышло."
if [ "$got" -ge "$PASS" ]; then echo "Результат: СДАНО"; exit 0; else echo "Результат: НЕ СДАНО"; exit 1; fi
