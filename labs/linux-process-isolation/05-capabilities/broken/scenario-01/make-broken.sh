#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: setcap +p (вместо +ep) — привилегия в
# permitted, но не effective; bind :80 от nobody всё равно отказывает.
# Enforcement bind проверяется на реальном хосте (на WSL2 file-cap bind не действует).
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
for t in python3 setcap getcap ss; do
  command -v "$t" >/dev/null || { echo "нет $t — sudo ./00-setup/install.sh"; exit 1; }
done

PY=/tmp/lpi-pyweb; cp "$(command -v python3)" "$PY"; chmod 0755 "$PY"
setcap cap_net_bind_service+p "$PY"          # БАГ: +p вместо +ep
echo "getcap: $(getcap "$PY")"

pkill -f "$PY -m http.server" 2>/dev/null; sleep 0.2
su -s /bin/bash nobody -c "exec $PY -m http.server 80 --bind 127.0.0.1" >/dev/null 2>&1 &
pid=$!; r=NOTBOUND
for _ in $(seq 1 15); do
  ss -tln '( sport = :80 )' 2>/dev/null | grep -q :80 && { r=BOUND; break; }
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.15
done
kill "$pid" 2>/dev/null; wait 2>/dev/null
echo "nobody :80 (+p) → $r   (ожидаемо NOTBOUND: cap в permitted, не effective)"

setcap -r "$PY" 2>/dev/null || true; rm -f "$PY"
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-effective-flag/fix.sh"
