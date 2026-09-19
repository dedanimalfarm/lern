#!/usr/bin/env bash
# Вставляет/обновляет блок навигации «предыдущий · индекс · следующий» в README
# модулей и проектов. Идемпотентно: блок ограничен маркерами <!-- NAV --> /
# <!-- /NAV --> и при повторном запуске перезаписывается.
#
# Порядок: модули — по номеру (01..30), проекты — по порядку прохождения из
# docs/02-learning-path.md (A -> B -> D -> E -> F). Блок ставится сразу после
# строки «⏱ время · сложность · пререквизиты».
set -euo pipefail

cd "$(dirname "$0")/../.."   # k8s root

python3 - <<'PY'
import pathlib, re

ROOT = pathlib.Path('.').resolve()
mods = sorted(p for p in (ROOT / 'modules').iterdir() if (p / 'README.md').exists())
proj_order = ['project-a-platform-namespace', 'project-b-stateful-service',
              'project-d-production-readiness', 'project-e-secure-platform',
              'project-c-broken-cluster-lab']
projs = [ROOT / 'projects' / n for n in proj_order if (ROOT / 'projects' / n / 'README.md').exists()]

def title(p):
    for line in (p / 'README.md').read_text(encoding='utf-8').split('\n'):
        if line.startswith('# '):
            return line[2:].strip()
    return p.name

def nav_block(chain, i, up):
    prev_l = f"⬅ [{chain[i-1].name}](../{chain[i-1].name}/)" if i > 0 else "⬅ начало"
    next_l = f"[{chain[i+1].name}](../{chain[i+1].name}/) ➡" if i < len(chain) - 1 else "конец ➡"
    return ("<!-- NAV -->\n"
            f"**{prev_l}** · [{up}](../../README.md) · "
            f"[карта обучения](../../docs/02-learning-path.md) · **{next_l}**\n"
            "<!-- /NAV -->")

changed = 0
for chain, up in ((mods, 'индекс курса'), (projs, 'индекс курса')):
    for i, p in enumerate(chain):
        f = p / 'README.md'
        s = f.read_text(encoding='utf-8')
        block = nav_block(chain, i, up)
        if '<!-- NAV -->' in s:
            new = re.sub(r'<!-- NAV -->.*?<!-- /NAV -->', lambda _m: block, s, flags=re.S)
        else:
            m = re.search(r'^> ?⏱[^\n]*\n', s, flags=re.M)
            if not m:
                print(f"!! {p.name}: нет строки ⏱ — пропущен")
                continue
            new = s[:m.end()] + '\n' + block + '\n' + s[m.end():]
        if new != s:
            f.write_text(new, encoding='utf-8')
            changed += 1
print(f"навигация обновлена: {changed} из {len(mods) + len(projs)}")
PY
