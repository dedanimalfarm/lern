#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: динамический бинарь (bash) в rootfs БЕЗ
# его .so-библиотек. Результат — обманчивая ошибка «No such file or directory»,
# хотя сам бинарь на месте. Разбор и фикс — в README.md рядом.
set -euo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

B=/lab/01-chroot-broken
rm -rf "$B"
install -d "$B/bin"
cp /bin/bash "$B/bin/"          # кладём bash, но НАМЕРЕННО не кладём библиотеки

echo "rootfs собран, bash на месте:"
ls -l "$B/bin/"
echo
echo "пытаемся войти → ожидаем обманчивую ошибку:"
chroot "$B" /bin/bash -c 'echo inside' || true
echo
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-missing-libs/fix.sh"
