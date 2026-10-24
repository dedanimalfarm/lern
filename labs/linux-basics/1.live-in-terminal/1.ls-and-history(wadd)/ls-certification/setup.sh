#!/usr/bin/env bash
# Арена для сертификации «The Lord of the LiSt» — каталог с файлами для задач из tasks.txt.
#
# Данные подобраны так, чтобы у каждой задачи был свой вывод, ни на что не похожий:
# в logs у файлов разные размер и mtime, и порядки -S и -t не совпадают ни друг с другом,
# ни с алфавитом. Иначе неверный флаг мог бы случайно дать «правильный» порядок.
# Даты заданы явно, поэтому арена одинакова на любой машине.
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

for c in ls touch ln mkdir head yes timeout; do
  command -v "$c" >/dev/null || { echo "Нет команды $c — установите coreutils."; exit 2; }
done

# Права как в карточке: файлы -rw-r--r--, каталоги drwxr-xr-x.
umask 022

# Лог заданного размера из повторяющегося текста и с заданным временем изменения (mtime).
# head читает из подстановки <(...), а не из конвейера: при pipefail yes, оборванный
# по SIGPIPE, иначе завершил бы весь скрипт с ошибкой.
log() {
  head -c "$2" < <(yes 'one command to list them all') > "logs/$1"
  touch -d "$3" "logs/$1"
}

make_arena() {
  mkdir -p "$ARENA"
  cd "$ARENA"
  mkdir -p etc words logs docs releases/v1 releases/v2 deep/a/b/c .config

  # Корень арены: обычные и скрытые файлы, исполняемый файл, обе ссылки.
  printf 'ls is fun\n' > notes.txt
  ln notes.txt hard.txt                     # жёсткая ссылка: тот же inode, счётчик ссылок 2
  ln -s notes.txt link-to-notes             # символическая ссылка: свой inode, тип l
  printf '#!/bin/sh\necho "one command to list them all"\n' > run.sh
  chmod 755 run.sh                          # ls -F пометит звёздочкой
  printf 'Arena for The Lord of the LiSt certification. Tasks: tasks.txt\n' > README
  printf 'you found me\n' > .hidden-note
  printf 'theme=dark\n' > .config/settings

  # etc: шаблон *.conf должен отсечь resolv.conf.bak и файлы без расширения.
  for f in host.conf nsswitch.conf sysctl.conf resolv.conf.bak fstab hosts; do
    printf '# %s\n' "$f" > "etc/$f"
  done

  # words: под ?a?? подходят bash ball data java mail tail, под [ab]* — apple area ball banana bash.
  for f in apple area ball banana bash cat cello data dog java mail tail; do
    : > "words/$f"
  done

  # logs. Порядок, свежие и большие — первыми:
  #   -t  mtime: syslog auth.log cron.log kern.log boot.log syslog.1.gz boot.log.1.gz
  #   -S  size:  syslog kern.log cron.log auth.log syslog.1.gz boot.log boot.log.1.gz
  log auth.log       3000 '2026-03-05 10:00'
  log boot.log        500 '2026-03-01 08:00'
  log cron.log       8000 '2026-03-03 12:00'
  log kern.log      12000 '2026-03-02 09:00'
  log syslog        20000 '2026-03-06 23:59'
  log syslog.1.gz    1500 '2026-02-27 23:59'
  log boot.log.1.gz   200 '2026-02-20 08:00'

  # docs: по алфавиту agenda.pdf beta.txt notes.md report.txt zeta.md,
  # по расширению (-X) — notes.md zeta.md agenda.pdf beta.txt report.txt.
  for f in agenda.pdf beta.txt notes.md report.txt zeta.md; do
    printf '%s\n' "$f" > "docs/$f"
  done

  # current -> releases/v2: ls -l current покажет саму ссылку, ls -l current/ — содержимое v2.
  printf 'version=1\n' > releases/v1/app.conf
  printf 'version=2\n' > releases/v2/app.conf
  printf 'v2: faster listings\n' > releases/v2/CHANGELOG
  ln -s releases/v2 current

  printf 'X marks the spot\n' > deep/a/b/c/treasure.txt

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
