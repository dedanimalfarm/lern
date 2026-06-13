#!/bin/bash
# Проверка решений модуля 06: Резервное копирование
SOLUTION_FILE="solution.sh"
DB_NAME="pagila"
DATE=$(date +%Y-%m-%d)
BACKUP_FILE="/tmp/pagila_${DATE}.dump"

if [ ! -f "$SOLUTION_FILE" ]; then
    echo "❌ Файл $SOLUTION_FILE не найден!"
    exit 1
fi

# Делаем скрипт исполняемым
chmod +x "$SOLUTION_FILE"

echo "🔍 Проверка решения модуля 06: Резервное копирование"
echo "============================================="

# Запуск решения студента
OUTPUT=$(./solution.sh 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Скрипт solution.sh завершился с ошибкой (код $EXIT_CODE)."
    echo "Лог выполнения:"
    echo "$OUTPUT"
    exit 1
fi

# Проверка вывода
if [[ "$OUTPUT" != *"Резервное копирование и выборочное восстановление успешно завершено!"* ]]; then
    echo "❌ Ожидаемое сообщение об успешном завершении не найдено в выводе!"
    echo "Вывод скрипта:"
    echo "$OUTPUT"
    exit 1
fi

# Проверка существования файла бэкапа
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Файл резервной копии $BACKUP_FILE не найден!"
    exit 1
fi

# Проверка размера бэкапа
if [ ! -s "$BACKUP_FILE" ]; then
    echo "❌ Созданный файл резервной копии пуст!"
    exit 1
fi

# Автоопределение метода подключения к БД для верификации данных
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="sudo -u postgres psql -d $DB_NAME"
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d $DB_NAME"
else
    echo "❌ Не удалось подключиться к БД $DB_NAME для проверки результатов"
    exit 1
fi

# Проверка наличия данных в восстановленной таблице
COUNT=$(eval "(cd /tmp && $PSQL_CMD -t -A -c \"SELECT COUNT(*) FROM film_category;\")" 2>/dev/null)
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
    echo "❌ Восстановленная таблица film_category пуста или не существует!"
    exit 1
fi

# Удаление тестового файла бэкапа
rm -f "$BACKUP_FILE"

echo "✅ Проверка пройдена! Бэкап создан, таблица успешно восстановлена."
