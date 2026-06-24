#!/bin/bash
# Вставляет «## Оглавление» с маркерами <!-- TOC --> / <!-- /TOC --> после
# заголовка H1 в README модулей/проектов, у которых TOC ещё нет.
#
# Якоря генерируются по правилам GitHub (github-slugger): текст в нижний
# регистр, выкидываются все символы кроме букв/цифр/«_»/«-»/пробела (КИРИЛЛИЦА
# СОХРАНЯЕТСЯ — \p{L}), пробелы -> «-», без обрезки; повторяющиеся заголовки
# дедуплицируются суффиксом -1, -2 … (первое вхождение — без суффикса).
# Старая awk-реализация резала кириллицу (`[^a-z0-9_ -]`) и не делала dedup —
# из-за этого якоря во всех модулях были битыми на GitHub.
set -euo pipefail

cd "$(dirname "$0")/../../" # k8s root

for dir in modules/* projects/*; do
  [[ -f "$dir/README.md" ]] || continue

  if grep -q "<!-- TOC -->" "$dir/README.md"; then
    echo "Skipping $dir - TOC exists"
    continue
  fi

  echo "Adding TOC to $dir"
  python3 - "$dir/README.md" <<'PY'
import re, sys, unicodedata

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")

def slug(s):
    s = s.lower()
    out = "".join(c for c in s if c.isalnum() or c in " -_" or unicodedata.combining(c))
    return out.replace(" ", "-")

# Заголовки в порядке документа с дедупликацией якорей (как на GitHub).
seen, headers, in_fence = {}, [], False
for ln in lines:
    if ln.lstrip().startswith("```"):
        in_fence = not in_fence
        continue
    if in_fence:
        continue
    m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", ln)
    if not m:
        continue
    lvl, txt = len(m.group(1)), m.group(2)
    base = slug(txt)
    n = seen.get(base, 0)
    seen[base] = n + 1
    headers.append((lvl, txt, base if n == 0 else f"{base}-{n}"))

toc = ["## Оглавление", "<!-- TOC -->"]
for lvl, txt, anchor in headers:
    if lvl not in (2, 3) or txt.strip().lower() == "оглавление":
        continue
    indent = "  " if lvl == 3 else ""
    toc.append(f"{indent}- [{txt}](#{anchor})")
toc += ["<!-- /TOC -->", ""]

# Вставляем блок сразу после первого H1.
out, done = [], False
for ln in lines:
    out.append(ln)
    if not done and re.match(r"^# ", ln):
        out.append("")
        out.extend(toc)
        done = True
open(path, "w", encoding="utf-8").write("\n".join(out))
PY
done
