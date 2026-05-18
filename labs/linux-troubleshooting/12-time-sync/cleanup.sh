#!/usr/bin/env bash
echo "Возвращаем NTP-синхронизацию ..."
sudo timedatectl set-ntp true
sleep 5
timedatectl
