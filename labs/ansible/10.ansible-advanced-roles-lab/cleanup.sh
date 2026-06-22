#!/bin/bash
set -euo pipefail

echo "==> Очистка ресурсов лабораторной работы №10..."

rm -f ansible.cfg
rm -rf roles/
rm -rf /tmp/ansible_cache

echo "✅ Очистка завершена!"
