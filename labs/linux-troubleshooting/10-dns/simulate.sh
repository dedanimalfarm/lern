#!/usr/bin/env bash
# Ломаем резолв github.com через /etc/hosts
echo "Подменяем github.com на 192.0.2.1 в /etc/hosts ..."
if ! grep -q '^192\.0\.2\.1[[:space:]]\+github\.com' /etc/hosts; then
    echo "192.0.2.1   github.com" | sudo tee -a /etc/hosts >/dev/null
fi
# Сбросим кеш systemd-resolved, если он есть
sudo resolvectl flush-caches 2>/dev/null || true
echo "Готово. Теперь 'curl https://github.com' не работает, но 'dig github.com' возвращает правильный IP."
echo "Подсказка: сравни 'dig +short github.com' и 'getent hosts github.com'."
