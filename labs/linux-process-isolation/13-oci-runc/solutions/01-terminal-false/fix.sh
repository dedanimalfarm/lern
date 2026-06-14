#!/usr/bin/env bash
# Чинит инцидент scenario-01: process.terminal=false → runc run работает без tty.
# rootfs — alpine (static /bin/sh).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
for t in runc python3 tar; do command -v "$t" >/dev/null || { echo "нет $t"; exit 1; }; done

B=/lab/13-fix/bundle
A=/lab/10/alpine
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
rm -rf /lab/13-fix; mkdir -p "$B/rootfs"
if [[ -x "$A/bin/sh" ]]; then cp -a "$A/." "$B/rootfs/"; else curl -fsSL "$URL" 2>/dev/null | tar -xz -C "$B/rootfs" 2>/dev/null; fi
( cd "$B" && runc spec )

python3 - "$B/config.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d['process']['terminal'] = False
d['process']['args'] = ['/bin/sh', '-c', 'echo runc-OK hostname=$(hostname) uid=$(id -u)']
json.dump(d, open(p, 'w'))
PY

echo "runc run (terminal=false):"
( cd "$B" && runc run ok ) 2>&1 | head -2

runc delete --force ok 2>/dev/null || true
rm -rf /lab/13-fix
