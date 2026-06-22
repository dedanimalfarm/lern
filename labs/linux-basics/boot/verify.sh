#!/bin/bash
set -euo pipefail

echo "=== Проверка модуля: Процесс загрузки Linux ==="

# Проверка наличия файла
FILE="$HOME/boot_info.txt"
if [ ! -f "$FILE" ]; then
    echo "❌ Ошибка: Файл $FILE не найден."
    echo "Убедитесь, что вы выполнили практическое задание."
    exit 1
fi

# Проверка содержимого файла (ожидаем target)
CONTENT=$(cat "$FILE")
if [[ "$CONTENT" == *.target ]]; then
    echo "✅ Успех: Файл $FILE содержит корректный target ($CONTENT)."
    echo "Модуль успешно пройден!"
else
    echo "❌ Ошибка: Файл $FILE содержит неверные данные ('$CONTENT')."
    echo "Ожидалось название target (например, multi-user.target или graphical.target)."
    exit 1
fi
