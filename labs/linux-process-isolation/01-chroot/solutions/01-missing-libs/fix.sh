#!/usr/bin/env bash
# Чинит инцидент scenario-01: докладывает в rootfs все .so, которые показывает
# ldd, по тем же абсолютным путям — после этого динамический bash запускается.
set -euo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

B=/lab/01-chroot-broken
[[ -x "$B/bin/bash" ]] || {
  echo "сначала собери поломку: sudo 01-chroot/broken/scenario-01/make-broken.sh" >&2
  exit 1
}

echo "ldd показывает зависимости bash:"
ldd /bin/bash

echo "копируем каждую библиотеку по тому же пути внутрь rootfs:"
ldd /bin/bash | grep -oE '/[^ ]+\.so[^ ]*' | while read -r lib; do
  install -D "$lib" "$B$lib"
  echo "  + $lib"
done

echo
echo "повторный вход — теперь работает:"
chroot "$B" /bin/bash -c 'echo inside-OK'
