#!/usr/bin/env bash
# cleanup: выгружаем профиль (если AppArmor активен) и сносим установленный скрипт.
set -uo pipefail
PROFILE=/etc/apparmor.d/usr.local.bin.secret-reader.sh
if [[ -d /sys/kernel/security/apparmor && -f "$PROFILE" ]]; then
  apparmor_parser -R "$PROFILE" 2>/dev/null || true
fi
rm -f "$PROFILE" /usr/local/bin/secret-reader.sh /tmp/aa-test.log /var/log/aa-test.log 2>/dev/null || true
echo "[OK] cleanup 07-apparmor"
