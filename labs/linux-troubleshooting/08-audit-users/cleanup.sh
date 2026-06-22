#!/usr/bin/env bash
# Очистка для лабы 08-audit-users
set -uo pipefail

echo "Удаляем правило auditd..."
auditctl -W /tmp/top_secret.txt -p wa -k secret_watch 2>/dev/null || true

echo "Удаляем временные файлы..."
rm -f /tmp/top_secret.txt
rm -f /tmp/audit_report.txt

echo "Очистка завершена!"
