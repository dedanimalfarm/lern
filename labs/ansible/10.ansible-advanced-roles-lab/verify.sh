#!/bin/bash
set -euo pipefail

echo "==> Проверка выполнения лабораторной работы №10..."

if [ ! -f "ansible.cfg" ]; then
    echo "❌ Ошибка: Файл ansible.cfg не найден. Убедитесь, что вы создали его и настроили кеширование фактов."
    exit 1
fi

if ! grep -q "fact_caching" "ansible.cfg"; then
    echo "❌ Ошибка: В ansible.cfg не включено кеширование (fact_caching)."
    exit 1
fi

if [ ! -d "roles" ]; then
    echo "❌ Ошибка: Директория roles не найдена. Вы создали роли?"
    exit 1
fi

has_meta=false
for meta in $(find roles -name "main.yml" | grep "meta/main.yml" || true); do
    if grep -q "dependencies:" "$meta"; then
        has_meta=true
        break
    fi
done

if [ "$has_meta" = false ]; then
    echo "❌ Ошибка: Не найдены зависимости в meta/main.yml ни для одной из ролей."
    exit 1
fi

has_molecule=false
if find roles -type d -name "molecule" | grep -q "molecule"; then
    has_molecule=true
fi

if [ "$has_molecule" = false ]; then
    echo "⚠️  Предупреждение: Директория molecule не найдена. Рекомендуется настроить Molecule."
fi

echo "✅ Проверка пройдена! Лабораторная работа выполнена успешно."
