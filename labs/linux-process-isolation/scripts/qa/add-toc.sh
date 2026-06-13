#!/usr/bin/env bash
# Генерация оглавления (TOC) в README модулей — host-bash аналог k8s
# scripts/qa/add-toc.sh. Идемпотентен: если в README уже есть маркер
# <!-- TOC -->, файл пропускается (правьте TOC руками внутри маркеров).
#
# TOC собирается из заголовков ## и ### и вставляется сразу после строки «# …».
# Якоря строятся по той же логике, что в k8s-лабах (lower-case, выкидываются
# все не-[a-z0-9_ -] символы) — для кириллицы это даёт «свёрнутые» якоря вида
# (#-), ровно как в эталонных модулях 29/30. Это сознательная совместимость
# со стандартом, а не баг.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

for dir in [0-9][0-9]-*; do
  readme="$dir/README.md"
  [[ -f "$readme" ]] || continue
  # Только модули, заявившие стандарт (есть verify/verify.sh): не насыпаем TOC
  # в ещё не сконвертированные модули и в служебный 00-setup.
  [[ -f "$dir/verify/verify.sh" ]] || continue

  if grep -q "<!-- TOC -->" "$readme"; then
    echo "skip $dir (TOC уже есть)"
    continue
  fi
  echo "add TOC → $dir"

  TOC=$(grep -E '^(##|###) ' "$readme" | awk '
    {
      level = length($1);
      sub(/^#+ /, "");
      title = $0;
      link = tolower(title);
      gsub(/[^a-z0-9_ -]/, "", link);
      gsub(/ /, "-", link);
      indent = "";
      for (i = 3; i <= level; i++) indent = indent "  ";
      print indent "- [" title "](#" link ")"
    }')

  awk -v toc="## Оглавление\n<!-- TOC -->\n$TOC\n<!-- /TOC -->\n" '
    /^# / && !done { print $0; print "\n" toc; done=1; next }
    { print $0 }
  ' "$readme" > "$readme.tmp"
  mv "$readme.tmp" "$readme"
done
