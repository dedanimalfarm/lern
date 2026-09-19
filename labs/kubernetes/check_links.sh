#!/bin/bash
# Проверка относительных markdown-ссылок [text](path) на существование файла.
#
# Код возврата: 0 — все ссылки живые, 1 — есть битые (и они напечатаны).
# Раньше скрипт всегда возвращал 1: из-за `set -o pipefail` цепочка
# `grep | sed | while` внутри цикла давала 1 на каждом файле БЕЗ ссылок
# (grep ничего не нашёл), и статус последнего файла становился статусом
# скрипта. В CI это выглядело как «битые ссылки» при пустом выводе.
set -uo pipefail

broken=0

while IFS= read -r -d '' f; do
  dir=$(dirname "$f")
  # Извлечь ссылки вида [text](path), пропуская http(s)-ссылки и якоря
  links=$(grep -oP '\]\([^http][^)]+\)' "$f" | sed 's/^](//; s/)$//' || true)
  [ -z "$links" ] && continue
  while IFS= read -r link; do
    file_path="${link%%#*}"
    [ -z "$file_path" ] && continue
    if [ ! -e "$dir/$file_path" ]; then
      echo "BROKEN LINK in $f: $link"
      broken=$((broken + 1))
    fi
  done <<< "$links"
done < <(find . -name "*.md" -print0)

if [ "$broken" -gt 0 ]; then
  echo "битых ссылок: $broken"
  exit 1
fi
echo "markdown-ссылки: ок"
exit 0
