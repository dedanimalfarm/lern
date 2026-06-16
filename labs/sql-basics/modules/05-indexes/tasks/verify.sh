#!/bin/bash
# Проверка решений модуля 05: Индексы
SOLUTION_FILE="solution.sql"
DB_NAME="pagila"

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

echo "🔍 Проверка решений модуля 05: Индексы и оптимизация"
echo "============================================="

# Предварительное удаление индексов для обеспечения идемпотентности проверки
eval "(cd /tmp && $PSQL_CMD -c \"DROP INDEX IF EXISTS idx_film_rating_rate, idx_rental_not_returned, idx_film_covering, idx_customer_create_date;\")" > /dev/null 2>&1

# Создаем временный файл без DROP-команд для проверки существования созданных индексов
grep -vi "drop index" "$SOLUTION_FILE" > /tmp/solution_test.sql

if eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < /tmp/solution_test.sql" > /dev/null 2>&1; then
    # Проверяем существование индексов
    INDEX_1=$(eval "(cd /tmp && $PSQL_CMD -t -A -c \"SELECT COUNT(*) FROM pg_indexes WHERE indexname = 'idx_film_rating_rate';\")")
    INDEX_2=$(eval "(cd /tmp && $PSQL_CMD -t -A -c \"SELECT COUNT(*) FROM pg_indexes WHERE indexname = 'idx_rental_not_returned';\")")
    INDEX_3=$(eval "(cd /tmp && $PSQL_CMD -t -A -c \"SELECT COUNT(*) FROM pg_indexes WHERE indexname = 'idx_film_covering';\")")
    
    if [ "$INDEX_1" -eq 1 ] && [ "$INDEX_2" -eq 1 ] && [ "$INDEX_3" -eq 1 ]; then
        echo "✅ Все запросы выполнились без ошибок!"
        echo "✅ Все требуемые индексы (idx_film_rating_rate, idx_rental_not_returned, idx_film_covering) успешно созданы!"
    else
        echo "❌ Ошибка: некоторые индексы не были созданы!"
        [ "$INDEX_1" -ne 1 ] && echo "  - Отсутствует индекс idx_film_rating_rate"
        [ "$INDEX_2" -ne 1 ] && echo "  - Отсутствует индекс idx_rental_not_returned"
        [ "$INDEX_3" -ne 1 ] && echo "  - Отсутствует индекс idx_film_covering"
        # Чистим за собой
        eval "(cd /tmp && $PSQL_CMD -c \"DROP INDEX IF EXISTS idx_film_rating_rate, idx_rental_not_returned, idx_film_covering;\")" > /dev/null 2>&1
        exit 1
    fi
else
    echo "❌ В запросах обнаружена синтаксическая ошибка."
    echo "Подробности:"
    eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi

# Очистка стенда после проверки
eval "(cd /tmp && $PSQL_CMD -c \"DROP INDEX IF EXISTS idx_film_rating_rate, idx_rental_not_returned, idx_film_covering;\")" > /dev/null 2>&1
rm -f /tmp/solution_test.sql
