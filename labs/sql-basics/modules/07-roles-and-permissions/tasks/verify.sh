#!/bin/bash
# Проверка решений модуля 07: Roles & Permissions
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

echo "🔍 Проверка решений модуля 07: Roles & Permissions"
echo "============================================="

# Проверка выполнения SQL-скрипта
if eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" > /dev/null 2>&1; then
    echo "✅ Все запросы выполнились без ошибок!"
    
    echo "⏳ Проверка корректности выданных прав..."
    ORDERS_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_table_privilege('bi_user', 'orders', 'SELECT');\"" 2>/dev/null)
    USERS_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_table_privilege('bi_user', 'users', 'SELECT');\"" 2>/dev/null)
    
    if [ "$ORDERS_PRIV" = "t" ] && [ "$USERS_PRIV" = "f" ]; then
        echo "✅ Права пользователя bi_user настроены корректно (Least Privilege соблюден)!"
        exit 0
    else
        echo "❌ Права пользователя bi_user настроены неверно!"
        echo "Доступ к orders: $ORDERS_PRIV (ожидается t)"
        echo "Доступ к users: $USERS_PRIV (ожидается f)"
        exit 1
    fi
else
    echo "❌ В запросах обнаружена ошибка."
    echo "Подробности:"
    eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi
