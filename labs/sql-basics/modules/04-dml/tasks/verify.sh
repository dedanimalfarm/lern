#!/bin/bash
# Проверка решений модуля 04: DML
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

echo "🔍 Проверка решений модуля 04: DML"
echo "============================================="

# Предварительная очистка данных для обеспечения идемпотентности проверки
eval "(cd /tmp && $PSQL_CMD -c \"DELETE FROM users WHERE email IN ('new@example.com', 'test@mail.com'); DELETE FROM products WHERE name = 'Флешка';\")" > /dev/null 2>&1

# Проверка синтаксиса через stdin (cd /tmp решает проблему прав на чтение /root для пользователя postgres)
if eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" > /dev/null 2>&1; then
    echo "✅ Все запросы выполнились без ошибок!"
else
    echo "❌ В запросах обнаружена синтаксическая ошибка."
    echo "Подробности:"
    eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi
