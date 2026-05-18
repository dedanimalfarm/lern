#!/usr/bin/env bash

# Требует root: без него нельзя ни понизить лимит ядра,
# ни корректно проверить поведение «слабой машины».
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Запусти через sudo: sudo ./simulate.sh"
    exit 1
fi

# Понижаем лимит, чтобы 15000 watch'ей точно не влезли.
# На современных Ubuntu/Debian дефолт может быть уже выше 8192 — иначе лаба не сломается.
# Когда студент уже поднял лимит и хочет проверить, что это помогло —
# запускает с KEEP_LIMIT=1 sudo ./simulate.sh, и тогда мы лимит не трогаем.
ORIG_LIMIT=$(sysctl -n fs.inotify.max_user_watches)
if [[ "${KEEP_LIMIT:-0}" != "1" ]]; then
    sysctl -w fs.inotify.max_user_watches=8192 >/dev/null
fi

echo "Создаём 15000 тестовых файлов в /tmp/inotify_test ..."
mkdir -p /tmp/inotify_test
rm -rf /tmp/inotify_test/*
seq 1 15000 | xargs -I{} -P 10 touch /tmp/inotify_test/file_{}

echo "Пытаемся подписаться на изменения через inotify (raw-syscall, без зависимостей) ..."

# Используем inotify напрямую через ctypes — не нужны ни pyinotify, ни pip3.
cat << 'PYTHON' > /tmp/test_inotify.py
import ctypes, os, sys
libc = ctypes.CDLL("libc.so.6", use_errno=True)
IN_MODIFY = 0x00000002

fd = libc.inotify_init1(0)
if fd < 0:
    sys.exit(f"inotify_init1 failed: {os.strerror(ctypes.get_errno())}")

directory = "/tmp/inotify_test"
count = 0
for name in os.listdir(directory):
    path = os.path.join(directory, name).encode()
    wd = libc.inotify_add_watch(fd, path, IN_MODIFY)
    if wd < 0:
        err = ctypes.get_errno()
        print(f"ОШИБКА: после {count} watches: {os.strerror(err)} (errno={err})")
        print("Похоже, исчерпан лимит fs.inotify.max_user_watches.")
        sys.exit(1)
    count += 1

print(f"УСПЕХ! Удалось подписаться на {count} файлов.")
PYTHON

python3 /tmp/test_inotify.py
EXIT_CODE=$?

# Чистим тестовые файлы, но НЕ возвращаем лимит — это домашка для студента.
rm -rf /tmp/inotify_test /tmp/test_inotify.py

if [ $EXIT_CODE -eq 0 ]; then
    echo
    echo "Отличная работа! Лимит ядра уже достаточно высокий."
else
    echo
    echo "Тест провален. Текущий лимит: $(sysctl -n fs.inotify.max_user_watches)"
    echo "Подними его командой:  sudo sysctl -w fs.inotify.max_user_watches=524288"
    echo "(До запуска лабы было: $ORIG_LIMIT)"
fi
