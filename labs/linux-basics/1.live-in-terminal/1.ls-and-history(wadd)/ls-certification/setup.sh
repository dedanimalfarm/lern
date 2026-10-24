#!/usr/bin/env bash
# Арена для сертификации «Lord of the LiSts» — каталог с файлами для задач из tasks.txt.
#
# Данные подобраны так, чтобы у каждой задачи был свой вывод, ни на что не похожий:
# в logs у файлов разные размер, mtime и atime, и три порядка (-S, -t, -u) не совпадают
# ни друг с другом, ни с алфавитом. Иначе неверный флаг мог бы случайно дать «правильный»
# порядок. Даты заданы явно, поэтому арена одинакова на любой машине.
#
# Root не нужен. Скрипт ничего не удаляет и не перезаписывает: если арена или файл ответов
# уже есть, он их не трогает. Пересоздавать арену не нужно — ls её только читает.
#
#   LS_ARENA    где создать арену         (по умолчанию ~/ls-arena)
#   LS_ANSWERS  куда положить файл ответов (по умолчанию ~/ls-answers.txt)
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")
ARENA=${LS_ARENA:-$HOME/ls-arena}
ANSWERS=${LS_ANSWERS:-$HOME/ls-answers.txt}

for c in ls du touch ln mkdir head yes timeout; do
  command -v "$c" >/dev/null || { echo "Нет команды $c — установите coreutils."; exit 2; }
done

# Права как в карточке: файлы -rw-r--r--, каталоги drwxr-xr-x.
umask 022

# Файл заданного размера из повторяющегося текста. Не из нулей: разреженный файл из нулей
# занимал бы на диске меньше своего размера, и ls -s показывал бы не то, что ждёт задача.
# head читает из подстановки <(...), а не из конвейера: при pipefail yes, оборванный
# по SIGPIPE, иначе завершил бы весь скрипт с ошибкой.
fill() { head -c "$2" < <(yes 'one command to list them all') > "$1"; }

# Лог: размер, время изменения (mtime) и время последнего чтения (atime).
log() {
  fill "logs/$1" "$2"
  touch -m -d "$3" "logs/$1"
  touch -a -d "$4" "logs/$1"
}

make_arena() {
  mkdir -p "$ARENA"
  cd "$ARENA"
  mkdir -p etc words logs docs chapters releases/v1 releases/v2 deep/a/b/c bigdir .config

  # Корень арены: обычные, скрытые, исполняемый файл, обе ссылки, имя с пробелом.
  printf 'ls is fun\n' > notes.txt          # 10 байт, но на диске один блок: ls -s покажет 4
  ln notes.txt hard.txt                     # жёсткая ссылка: тот же inode, счётчик ссылок 2
  ln -s notes.txt link-to-notes             # символическая ссылка: свой inode, тип l
  printf '#!/bin/sh\necho "one command to list them all"\n' > run.sh
  chmod 755 run.sh                          # ls -F пометит звёздочкой
  printf 'a space in the name\n' > 'my file.txt'
  : > Apple.txt                             # заглавная и строчная: их порядок
  : > banana.txt                            # зависит от локали (задача 38)
  printf 'Arena for the Lord of the LiSts certification. Tasks: tasks.txt\n' > README
  printf 'you found me\n' > .hidden-note
  printf 'theme=dark\n' > .config/settings

  # etc: шаблон *.conf должен отсечь resolv.conf.bak и файлы без расширения.
  for f in host.conf nsswitch.conf sysctl.conf resolv.conf.bak fstab hosts; do
    printf '# %s\n' "$f" > "etc/$f"
  done

  # words: под ?a?? подходят bash ball data java mail tail, под [bc]* — ball banana bash cat cello.
  for f in apple area ball banana bash cat cello data dog java mail tail; do
    : > "words/$f"
  done

  # logs. Порядок, свежие и большие — первыми:
  #   -t  mtime: syslog auth.log cron.log kern.log boot.log syslog.1.gz boot.log.1.gz
  #   -S  size:  syslog kern.log cron.log auth.log syslog.1.gz boot.log boot.log.1.gz
  #   -u  atime: boot.log syslog cron.log kern.log auth.log syslog.1.gz boot.log.1.gz
  # ctime выставить нельзя: это время последней правки метаданных, то есть момент
  # запуска setup.sh. Поэтому в ls -ltc видна сегодняшняя дата, а не мартовская.
  log auth.log       3000 '2026-03-05 10:00' '2026-03-20 09:00'
  log boot.log        500 '2026-03-01 08:00' '2026-03-25 12:00'
  log cron.log       8000 '2026-03-03 12:00' '2026-03-22 07:30'
  log kern.log      12000 '2026-03-02 09:00' '2026-03-21 18:45'
  log syslog        20000 '2026-03-06 23:59' '2026-03-24 06:00'
  log syslog.1.gz    1500 '2026-02-27 23:59' '2026-03-11 10:00'
  log boot.log.1.gz   200 '2026-02-20 08:00' '2026-03-10 10:00'

  # docs: по алфавиту agenda.pdf beta.txt notes.md report.txt zeta.md,
  # по расширению (-X) — notes.md zeta.md agenda.pdf beta.txt report.txt.
  for f in agenda.pdf beta.txt notes.md report.txt zeta.md; do
    printf '%s\n' "$f" > "docs/$f"
  done

  # chapters: по алфавиту ch1 ch10 ch11 ch2 ch3, естественный порядок (-v) — ch1 ch2 ch3 ch10 ch11.
  for n in 1 2 3 10 11; do
    printf 'chapter %s\n' "$n" > "chapters/ch$n.txt"
  done

  # current -> releases/v2: ls -l current покажет ссылку, ls -l current/ — содержимое v2.
  printf 'version=1\n' > releases/v1/app.conf
  printf 'version=2\n' > releases/v2/app.conf
  printf 'v2: faster listings\n' > releases/v2/CHANGELOG
  ln -s releases/v2 current

  printf 'X marks the spot\n' > deep/a/b/c/treasure.txt

  # bigdir: сам каталог занимает 4096 байт, а с содержимым — больше мегабайта (du -sh).
  fill bigdir/data.bin 1048576

  # Всем, кроме логов, одна дата. Каталоги тоже получают её здесь: создание файлов уже
  # закончено, а только оно меняет mtime каталога. -h — время самой ссылки, а не цели.
  find . -mindepth 1 ! -path './logs/*' -exec touch -h -d '2026-01-15 12:00' {} +
  touch -d '2026-01-15 12:00' .
}

if [ -e "$ARENA" ]; then
  echo "Арена уже есть: $ARENA — не трогаю (ls её только читает, пересоздавать не нужно)."
  echo "Если вы сами меняли файлы в арене, переименуйте её (mv) и запустите setup.sh снова."
else
  make_arena
  echo "Арена создана: $ARENA"
fi

if [ -e "$ANSWERS" ]; then
  echo "Файл ответов уже есть: $ANSWERS — не трогаю."
else
  cp "$HERE/answers-template.txt" "$ANSWERS"
  echo "Файл ответов создан: $ANSWERS"
fi

cat <<EOF

Дальше:
  1. Откройте задания: $HERE/tasks.txt
  2. Пробуйте команды в арене: cd $ARENA
  3. Впишите в $ANSWERS по одной команде на задачу.
  4. Проверьте: $HERE/check.sh
EOF
