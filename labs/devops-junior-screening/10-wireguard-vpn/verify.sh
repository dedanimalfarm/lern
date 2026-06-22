#!/bin/bash
set -euo pipefail

echo "==> Проверка выполнения лабораторной по WireGuard"

# Проверка 1: WireGuard установлен
if ! command -v wg &> /dev/null; then
    echo "❌ WireGuard (wg) не установлен!"
    exit 1
fi
echo "✅ WireGuard (wg) установлен."

# Проверка 2: Интерфейс поднят
if ! ip link show wg0 &> /dev/null; then
    echo "❌ Интерфейс wg0 не существует или не поднят!"
    exit 1
fi
echo "✅ Интерфейс wg0 поднят."

# Проверка 3: Файл конфигурации существует
if [ ! -f "/etc/wireguard/wg0.conf" ]; then
    echo "❌ Файл конфигурации /etc/wireguard/wg0.conf не найден!"
    exit 1
fi
echo "✅ Конфигурация wg0.conf найдена."

# Проверка 4: Systemd-сервис включен
if ! systemctl is-enabled wg-quick@wg0 &> /dev/null; then
    echo "⚠️ Сервис wg-quick@wg0 не добавлен в автозагрузку (systemctl enable). Это рекомендация."
else
    echo "✅ Сервис wg-quick@wg0 включен в автозагрузку."
fi

# Проверка 5: Наличие peer в wg show
if ! sudo wg show wg0 peers | grep -q .; then
    echo "❌ В настройках wg0 нет ни одного Peer!"
    exit 1
fi
echo "✅ Peer настроен."

# Проверка 6: IP-адрес интерфейса
WG_IP=$(ip -4 addr show wg0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
if [ -z "$WG_IP" ]; then
    echo "❌ Интерфейс wg0 не имеет IPv4 адреса!"
    exit 1
fi
echo "✅ Интерфейс wg0 имеет IP-адрес: $WG_IP"

echo "🎉 Все базовые проверки пройдены! Убедитесь, что пинг между пирами идет."
