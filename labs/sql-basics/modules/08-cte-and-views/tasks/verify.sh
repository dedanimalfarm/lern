#!/bin/bash
# Проверка решений модуля 08: CTE & Views
SOLUTION_FILE="solution.sql"
DB_NAME="shop_db"

if [ ! -f "$SOLUTION_FILE" ]; then
    echo "❌ Файл $SOLUTION_FILE не найден!"
    exit 1
fi

# Автоопределение метода подключения
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="sudo -u postgres psql -d $DB_NAME"
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d $DB_NAME"
else
    echo "❌ Не удалось подключиться к БД $DB_NAME"
    exit 1
fi

echo "🔍 Проверка решений модуля 08: CTE & Views"
echo "============================================="

# Проверка выполнения SQL-скрипта
if eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" > /dev/null 2>&1; then
    echo "✅ Все запросы выполнились без ошибок!"
    
    echo "⏳ Проверка материализованного представления..."
    HAS_MATVIEW=$(eval "$PSQL_CMD -tAc \"SELECT count(*) FROM pg_matviews WHERE matviewname = 'customer_stats';\"" 2>/dev/null)
    HAS_INDEX=$(eval "$PSQL_CMD -tAc \"SELECT count(*) FROM pg_indexes WHERE indexname = 'idx_customer_stats_user_id';\"" 2>/dev/null)
    
    if [ "$HAS_MATVIEW" -eq 1 ]; then
        echo "✅ Материализованное представление customer_stats успешно создано!"
        if [ "$HAS_INDEX" -eq 1 ]; then
            echo "✅ Индекс idx_customer_stats_user_id успешно создан!"
        else
            echo "⚠️ Индекс idx_customer_stats_user_id не найден (опционально)."
        fi
        exit 0
    else
        echo "❌ Материализованное представление customer_stats не найдено!"
        exit 1
    fi
else
    echo "❌ В запросах обнаружена ошибка."
    echo "Подробности:"
    eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi
