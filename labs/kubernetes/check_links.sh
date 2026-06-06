#!/bin/bash
# Проверка относительных markdown-ссылок [text](path) на существование файла.
# Использует find -print0 + while read (устойчиво к пробелам в путях; SC2044/SC2162).
set -uo pipefail

find . -name "*.md" -print0 | while IFS= read -r -d '' f; do
  dir=$(dirname "$f")
  # Извлечь ссылки вида [text](path), пропуская http(s)-ссылки
  grep -oP '\]\([^http][^)]+\)' "$f" | sed 's/^](//; s/)$//' | while IFS= read -r link; do
    # Отбросить #якоря
    file_path="${link%%#*}"
    [ -z "$file_path" ] && continue
    if [ ! -e "$dir/$file_path" ]; then
      echo "BROKEN LINK in $f: $link"
    fi
  done
done
