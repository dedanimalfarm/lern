#!/usr/bin/env bash
# Общие helper-функции для verify/*.sh всех модулей linux-process-isolation.
#
# Это host-bash аналог k8s-лабовского scripts/verify/helpers.sh. Разница в
# домене: здесь нет kubectl/namespace-объектов — «ресурсы» это процессы,
# точки монтирования, kernel-namespace и файлы cgroup. Контракт вывода тот же,
# что в k8s-лабах: каждая проверка печатает [OK] / [WARN] / [FAIL], а на первом
# FAIL скрипт обязан завершиться ненулевым кодом (этого добивается `set -e` в
# verify.sh + идиома `<условие> || fail "<текст>"`).
set -euo pipefail

ok()   { printf '[OK] %s\n'   "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
# fail печатает и возвращает 1; под `set -e` в вызывающем скрипте это валит
# прогон ровно на проваленной проверке — с понятным текстом, а не молча.
fail() { printf '[FAIL] %s\n' "$*"; return 1; }

# Почти всем модулям нужен НАСТОЯЩИЙ root: CLONE_NEWNS/CLONE_NEWPID, mount(2),
# chroot(2), запись в cgroup. На контейнерных хостах часть лаб не пройдёт.
need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] \
    || fail "нужен root (sudo) — модуль работает с namespace/mount/chroot"
}

# need_bin <утилита> — наличие бинаря в PATH (иначе подсказка про 00-setup).
need_bin() {
  command -v "$1" >/dev/null 2>&1 \
    || fail "не найдена утилита: $1 (поставь: sudo ./00-setup/install.sh)"
}

# require_file <путь> [человекочитаемое описание]
require_file() {
  local f="$1" desc="${2:-$1}"
  [[ -e "$f" ]] || fail "нет пути: $desc ($f)"
}

# assert_eq <ожидаемое> <фактическое> <описание>
assert_eq() {
  local exp="$1" act="$2" desc="$3"
  [[ "$exp" == "$act" ]] || fail "$desc: ожидалось '$exp', получено '$act'"
}

# assert_ne <не-ожидаемое> <фактическое> <описание>
assert_ne() {
  local nexp="$1" act="$2" desc="$3"
  [[ "$nexp" != "$act" ]] || fail "$desc: значение совпало с '$nexp', а не должно"
}

# require_succeeds <описание> <команда...> — команда обязана вернуть 0.
require_succeeds() {
  local desc="$1"; shift
  "$@" >/dev/null 2>&1 || fail "$desc (команда упала: $*)"
}

# require_fails <описание> <команда...> — команда ОБЯЗАНА упасть. Так мы
# проверяем границы изоляции (seccomp заблокировал вызов, cap отобран и т.п.).
require_fails() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc (команда прошла, ожидался отказ)"
  fi
}

# ns_inode <тип-ns> [chroot-rootfs] — inode kernel-namespace процесса.
# Ядро гарантирует: у процессов в РАЗНЫХ namespace inode-номера различаются, в
# одном — совпадают. Это самый честный способ доказать (не)изоляцию.
# Без второго аргумента — про текущий процесс; со вторым — внутри chroot.
ns_inode() {
  local kind="$1" root="${2:-}"
  if [[ -n "$root" ]]; then
    chroot "$root" /bin/stat -L -c %i "/proc/self/ns/$kind" 2>/dev/null || true
  else
    stat -L -c %i "/proc/self/ns/$kind" 2>/dev/null || true
  fi
}
