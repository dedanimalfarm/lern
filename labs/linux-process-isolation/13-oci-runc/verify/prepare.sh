#!/usr/bin/env bash
# prepare: собираем OCI-bundle из alpine rootfs (static musl /bin/sh, работает в
# минимальном контейнере — в отличие от динамического busybox на части хостов) +
# config.json через runc spec, terminal=false, команда-маркеры.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/verify/helpers.sh
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_root
need_bin runc
need_bin python3
need_bin tar

B=/lab/13-runc/bundle
A=/lab/10/alpine
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
rm -rf /lab/13-runc
mkdir -p "$B/rootfs"
if [[ -x "$A/bin/sh" ]]; then
  cp -a "$A/." "$B/rootfs/"                 # переиспользуем rootfs из этапов 10/11
else
  need_bin curl
  curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$B/rootfs" 2>/dev/null \
    || fail "не удалось скачать alpine rootfs (нет интернета на хосте?)"
fi
[[ -x "$B/rootfs/bin/sh" ]] || fail "rootfs без /bin/sh"

( cd "$B" && runc spec )
python3 - "$B/config.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d['process']['terminal'] = False
d['process']['args'] = ['/bin/sh', '-c',
                        'echo PID1=$(cat /proc/1/comm); echo HOST=$(hostname); echo UID=$(id -u)']
d['root']['readonly'] = False
json.dump(d, open(p, 'w'))
PY

ok "OCI-bundle готов: $B (alpine rootfs + config.json, terminal=false)"
