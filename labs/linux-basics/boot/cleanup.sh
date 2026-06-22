#!/bin/bash
set -euo pipefail

echo "=== Очистка среды: Процесс загрузки Linux ==="

FILE="$HOME/boot_info.txt"
if [ -f "$FILE" ]; then
    rm -f "$FILE"
    echo "✅ Файл $FILE успешно удален."
else
    echo "ℹ️ Файл $FILE не найден. Очистка не требуется."
fi

echo "Очистка завершена."
