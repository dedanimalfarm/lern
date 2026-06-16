#!/usr/bin/env bash
# Проверка усвоенных навыков лабы "Управление памятью в Linux".
# Скрипт САМ поднимает мини-стенды и САМ за собой убирает все ресурсы.
# Swap-часть требует root/sudo (без него — пропускается, не падает).
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
skip() { printf "  [SKIP] %s\n" "$1"; }
FAILED=0

ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

# --- 1) Demand paging: нетронутая anon-память даёт VSZ >> RSS ------------------
echo "=== 1) Demand paging (VSZ >> RSS у нетронутой памяти) ==="
python3 -c 'import mmap,os,time; m=mmap.mmap(-1,512*1024*1024); time.sleep(20)' >/dev/null 2>&1 &
VPID=$!
sleep 2
read -r VSZ RSS < <(ps -o vsz=,rss= -p "$VPID" 2>/dev/null | awk '{print $1+0, $2+0}')
kill "$VPID" 2>/dev/null || true
VSZ=${VSZ:-0}; RSS=${RSS:-0}
if [ "$VSZ" -gt 524288 ] && [ "$RSS" -lt 102400 ]; then
  ok "VSZ=${VSZ}KB (>512МБ), RSS=${RSS}KB (<100МБ) — страницы выделяются по требованию"
else
  fail "VSZ=${VSZ}KB RSS=${RSS}KB — ожидали VSZ>512МБ при RSS<100МБ"
fi

# --- 2) glibc возвращает heap ядру только по malloc_trim ----------------------
echo "=== 2) malloc_trim возвращает heap ядру ==="
OUT=$(python3 <<'PY'
import ctypes, os
libc = ctypes.CDLL("libc.so.6")
# Без restype malloc вернёт 32-битный int — на 64-бит адрес усечётся и memset
# напишет по битому адресу. Объявляем сигнатуры явно.
libc.malloc.restype = ctypes.c_void_p
libc.malloc.argtypes = [ctypes.c_size_t]
libc.free.argtypes = [ctypes.c_void_p]
libc.malloc_trim.argtypes = [ctypes.c_size_t]
def rss():
    with open(f"/proc/{os.getpid()}/status") as f:
        for l in f:
            if l.startswith("VmRSS:"): return int(l.split()[1])
    return 0
ptrs = [libc.malloc(1024) for _ in range(50_000)]
for p in ptrs: ctypes.memset(p, 0xAB, 1024)
a = rss()
for p in ptrs: libc.free(p)
b = rss()
libc.malloc_trim(0)
c = rss()
print(a, b, c)
PY
)
read -r M F T <<<"$OUT"
M=${M:-0}; F=${F:-0}; T=${T:-0}
if [ "$T" -lt "$F" ] && [ "$F" -gt 0 ]; then
  ok "RSS: malloc=${M}KB free=${F}KB trim=${T}KB — после trim память вернулась ядру"
else
  fail "malloc_trim не уменьшил RSS (malloc=${M} free=${F} trim=${T})"
fi

# --- 3) Полный жизненный цикл swap-файла (root) -------------------------------
echo "=== 3) Жизненный цикл swap-файла ==="
if [ "$ROOT" -eq 1 ]; then
  SWF=/swapfile-verify
  if [ -e "$SWF" ]; then
    fail "$SWF уже существует — удалите его и перезапустите"
  else
    if fallocate -l 256M "$SWF" 2>/dev/null && chmod 600 "$SWF" \
       && mkswap "$SWF" >/dev/null 2>&1 && swapon "$SWF" 2>/dev/null; then
      if swapon --show=NAME 2>/dev/null | grep -q "$SWF"; then
        ok "swap-файл создан, размечен (mkswap) и подключён (виден в swapon --show)"
      else
        fail "swap-файл не появился в swapon --show"
      fi
    else
      fail "не удалось создать/подключить swap-файл (ФС без поддержки swap?)"
    fi
    swapoff "$SWF" 2>/dev/null || true
    rm -f "$SWF"
    if swapon --show=NAME 2>/dev/null | grep -q "$SWF"; then
      fail "swap не снялся"
    else
      ok "swap-файл снят (swapoff) и удалён — за собой убрано"
    fi
  fi
else
  skip "не root — пропускаю swap-часть (нужен sudo)"
fi

# --- 4) Осиротевший SysV shm: детект и ТОЧЕЧНОЕ удаление -----------------------
echo "=== 4) SysV shm: детект осиротевшего и точечное удаление ==="
CREATE=$(ipcmk -M 32M 2>/dev/null)
SHMID=$(echo "$CREATE" | awk '{print $NF}')
if [ -n "${SHMID:-}" ] && ipcs -m | awk -v id="$SHMID" '$2==id && $6==0' | grep -q .; then
  ok "сегмент shmid=$SHMID создан и виден как осиротевший (nattch=0)"
else
  fail "не удалось создать/детектить SysV shm (shmid='${SHMID:-}')"
fi
if [ -n "${SHMID:-}" ]; then
  ipcrm -m "$SHMID" 2>/dev/null || true
  if ipcs -m | awk -v id="$SHMID" '$2==id' | grep -q .; then
    fail "сегмент $SHMID не удалён"
  else
    ok "сегмент удалён точечно по своему shmid (чужие сегменты не тронуты)"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "Навыки лабы подтверждены."
  exit 0
else
  echo "Есть проваленные проверки — см. [FAIL] выше."
  exit 1
fi
