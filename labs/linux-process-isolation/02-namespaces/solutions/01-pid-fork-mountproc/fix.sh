#!/usr/bin/env bash
# Чинит инцидент scenario-01: полная триада --pid --fork --mount-proc даёт
# корректный PID-namespace — внутри $$=1 и ps видит только свои процессы.
# shellcheck disable=SC2016  # $$ намеренно раскрывается во ВНУТРЕННЕМ bash
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }

echo "правильно — --pid --fork --mount-proc:"
unshare --pid --fork --mount-proc /bin/bash -c '
  echo "  \$\$=$$ (PID 1 в своём namespace)"
  echo "  ps -e: $(ps -e --no-headers | wc -l) процесса (только свои)"
  ps -e
'
