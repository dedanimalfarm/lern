#!/usr/bin/env bash
# cleanup: seccomp-фильтры эфемерны (умирают с процессом). Снимаем лишь временные
# копии helper'ов из /tmp, если остались от broken/solutions.
set -uo pipefail
rm -f /tmp/lpi-nonnp.py /tmp/lpi-scbpf.py 2>/dev/null || true
echo "[OK] cleanup 06-seccomp"
