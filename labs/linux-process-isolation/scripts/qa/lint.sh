#!/usr/bin/env bash
# Линт лабы (host-bash аналог k8s scripts/qa/lint.sh):
#   1) shellcheck по «стандартной» поверхности — scripts/ и verify/broken/
#      solutions/ конвертированных модулей (legacy-скрипты run.sh/check.sh
#      старого формата не гейтим: они снимаются по мере раскатки стандарта);
#   2) markdown-дисциплина: у каждого УЖЕ конвертированного модуля (признак —
#      наличие verify/verify.sh) в README обязаны быть блок <!-- TOC --> и
#      строка-метаданные «⏱ время · сложность · пререквизиты».
# Гонять до коммита; CI дублирует это на GitHub.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1
RC=0

echo "=== shellcheck (scripts/ + verify/broken/solutions) ==="
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -d '' -t SH < <(
    find . -maxdepth 1 -type f -name '*.sh' -print0
    find scripts 00-setup -type f -name '*.sh' -print0
    find . -type f -name '*.sh' \
      \( -path '*/verify/*' -o -path '*/broken/*' -o -path '*/solutions/*' \) \
      -not -path './legacy/*' -print0
  )
  if [[ ${#SH[@]} -gt 0 ]]; then
    shellcheck -x "${SH[@]}" || { echo "shellcheck: есть замечания"; RC=1; }
  fi
else
  echo "shellcheck не установлен — пропуск (apt-get install shellcheck)"
fi

echo "=== markdown-дисциплина конвертированных модулей ==="
for dir in [0-9][0-9]-*; do
  # Стандарт применяем только к модулям, заявившим его (есть verify/verify.sh).
  [[ -f "$dir/verify/verify.sh" ]] || continue
  readme="$dir/README.md"
  [[ -f "$readme" ]] || { echo "  $dir: нет README.md"; RC=1; continue; }
  grep -q '<!-- TOC -->' "$readme" \
    || { echo "  $dir/README.md: нет блока <!-- TOC --> (прогони scripts/qa/add-toc.sh)"; RC=1; }
  grep -q '⏱' "$readme" \
    || { echo "  $dir/README.md: нет строки '⏱ время · сложность · пререквизиты'"; RC=1; }
done

[[ $RC -eq 0 ]] && echo "Линт чист." || echo "Линт нашёл замечания."
exit $RC
