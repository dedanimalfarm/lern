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

# Предварительная очистка связанных объектов ролей в других базах данных (например, pagila)
if sudo -u postgres psql -d pagila -c "SELECT 1" >/dev/null 2>&1; then
    sudo -u postgres psql -d pagila -c "DROP OWNED BY bi_user CASCADE; DROP OWNED BY analytics_group CASCADE;" >/dev/null 2>&1 || true
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d pagila -c "SELECT 1" >/dev/null 2>&1; then
    PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d pagila -c "DROP OWNED BY bi_user CASCADE; DROP OWNED BY analytics_group CASCADE;" >/dev/null 2>&1 || true
fi

echo "🔍 Проверка решений модуля 07: Roles & Permissions"
echo "============================================="

# Проверка выполнения SQL-скрипта
if eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" > /dev/null 2>&1; then
    echo "✅ Все запросы выполнились без ошибок!"
    
    echo "⏳ Проверка корректности выданных прав..."
    DB_CONN_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_database_privilege('bi_user', 'shop_db', 'CONNECT');\"" 2>/dev/null)
    SCHEMA_USAGE_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_schema_privilege('bi_user', 'public', 'USAGE');\"" 2>/dev/null)
    ORDERS_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_table_privilege('bi_user', 'orders', 'SELECT');\"" 2>/dev/null)
    PRODUCTS_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_table_privilege('bi_user', 'products', 'SELECT');\"" 2>/dev/null)
    USERS_PRIV=$(eval "$PSQL_CMD -tAc \"SELECT has_table_privilege('bi_user', 'users', 'SELECT');\"" 2>/dev/null)
    
    if [ "$DB_CONN_PRIV" = "t" ] && [ "$SCHEMA_USAGE_PRIV" = "t" ] && [ "$ORDERS_PRIV" = "t" ] && [ "$PRODUCTS_PRIV" = "t" ] && [ "$USERS_PRIV" = "f" ]; then
        echo "✅ Права пользователя bi_user настроены корректно (Least Privilege соблюден)!"
        exit 0
    else
        echo "❌ Права пользователя bi_user настроены неверно!"
        echo "Подключение к shop_db: $DB_CONN_PRIV (ожидается t)"
        echo "Использование public: $SCHEMA_USAGE_PRIV (ожидается t)"
        echo "Доступ к orders: $ORDERS_PRIV (ожидается t)"
        echo "Доступ к products: $PRODUCTS_PRIV (ожидается t)"
        echo "Доступ к users: $USERS_PRIV (ожидается f)"
        exit 1
    fi
else
    echo "❌ В запросах обнаружена ошибка."
    echo "Подробности:"
    eval "(cd /tmp && $PSQL_CMD -v ON_ERROR_STOP=1) < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi
