#!/bin/bash
set -euo pipefail

echo "==> Очистка лабораторной по WireGuard"

# Остановка туннеля и отключение сервиса
if systemctl is-active wg-quick@wg0 &> /dev/null; then
    echo "Останавливаем wg-quick@wg0..."
    sudo systemctl stop wg-quick@wg0 || true
fi

if systemctl is-enabled wg-quick@wg0 &> /dev/null; then
    echo "Отключаем автозапуск wg-quick@wg0..."
    sudo systemctl disable wg-quick@wg0 || true
fi

# Прямое отключение интерфейса на всякий случай
if ip link show wg0 &> /dev/null; then
    echo "Удаляем интерфейс wg0..."
    sudo ip link delete dev wg0 || true
fi

# Удаление файлов WireGuard
echo "Удаляем ключи и конфигурации /etc/wireguard/..."
sudo rm -f /etc/wireguard/wg0.conf
sudo rm -f /etc/wireguard/server.key /etc/wireguard/server.pub
sudo rm -f /etc/wireguard/client.key /etc/wireguard/client.pub

# Удаление sysctl
if [ -f "/etc/sysctl.d/99-wg.conf" ]; then
    echo "Удаляем настройки forwarding..."
    sudo rm -f /etc/sysctl.d/99-wg.conf
    sudo sysctl --system || true
fi

# Удаление UFW правил (если ufw установлен)
if command -v ufw &> /dev/null; then
    echo "Удаляем правило 51820/udp из ufw (если есть)..."
    sudo ufw delete allow 51820/udp || true
fi

echo "✅ Очистка завершена! Не забудьте удалить правило 51820/udp из Security Groups вашего облачного провайдера, если оно там создавалось."
