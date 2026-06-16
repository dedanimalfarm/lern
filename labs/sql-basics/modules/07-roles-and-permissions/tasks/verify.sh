#!/bin/bash
# Проверка решений модуля 07: Роли и доступы
SOLUTION_FILE="solution.sql"
DB_NAME="pagila"

if [ ! -f "$SOLUTION_FILE" ]; then
    echo "❌ Файл $SOLUTION_FILE не найден!"
    exit 1
fi

echo "🔍 Проверка решения модуля 07: Роли и доступы"
echo "============================================="

# Автоопределение метода подключения (от имени суперпользователя)
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="sudo -u postgres psql -d $DB_NAME -t -A -c"
    PSQL_RUN="sudo -u postgres psql -d $DB_NAME"
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d $DB_NAME -t -A -c"
    PSQL_RUN="PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d $DB_NAME"
else
    echo "❌ Не удалось подключиться к БД $DB_NAME как суперпользователь"
    exit 1
fi

# Предварительная очистка связанных объектов ролей в других базах данных
if sudo -u postgres psql -d shop_db -c "SELECT 1" >/dev/null 2>&1; then
    sudo -u postgres psql -d shop_db -c "DROP OWNED BY bi_user CASCADE; DROP OWNED BY analytics_group CASCADE;" >/dev/null 2>&1 || true
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -c "SELECT 1" >/dev/null 2>&1; then
    PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -c "DROP OWNED BY bi_user CASCADE; DROP OWNED BY analytics_group CASCADE;" >/dev/null 2>&1 || true
fi

echo "⏳ Применение solution.sql..."

# Проверка выполнения SQL-скрипта
if eval "$PSQL_RUN -v ON_ERROR_STOP=1 < $SOLUTION_FILE" > /dev/null 2>&1; then
    echo "✅ Все запросы выполнились без ошибок!"
    
    echo "⏳ Проверка корректности выданных прав..."
    DB_CONN_PRIV=$(eval "$PSQL_CMD \"SELECT has_database_privilege('bi_user', 'pagila', 'CONNECT');\"" 2>/dev/null)
    SCHEMA_USAGE_PRIV=$(eval "$PSQL_CMD \"SELECT has_schema_privilege('bi_user', 'public', 'USAGE');\"" 2>/dev/null)
    PAYMENT_PRIV=$(eval "$PSQL_CMD \"SELECT has_table_privilege('bi_user', 'payment', 'SELECT');\"" 2>/dev/null)
    FILM_PRIV=$(eval "$PSQL_CMD \"SELECT has_table_privilege('bi_user', 'film', 'SELECT');\"" 2>/dev/null)
    ACTOR_PRIV=$(eval "$PSQL_CMD \"SELECT has_table_privilege('bi_user', 'actor', 'SELECT');\"" 2>/dev/null)
    
    if [ "$DB_CONN_PRIV" = "t" ] && [ "$SCHEMA_USAGE_PRIV" = "t" ] && [ "$PAYMENT_PRIV" = "t" ] && [ "$FILM_PRIV" = "t" ] && [ "$ACTOR_PRIV" = "f" ]; then
        echo "✅ Права пользователя bi_user настроены корректно (Least Privilege соблюден)!"
        exit 0
    else
        echo "❌ Права пользователя bi_user настроены неверно!"
        echo "Подключение к pagila: $DB_CONN_PRIV (ожидается t)"
        echo "Использование public: $SCHEMA_USAGE_PRIV (ожидается t)"
        echo "Доступ к payment: $PAYMENT_PRIV (ожидается t)"
        echo "Доступ к film: $FILM_PRIV (ожидается t)"
        echo "Доступ к actor: $ACTOR_PRIV (ожидается f)"
        exit 1
    fi
else
    echo "❌ В запросах обнаружена ошибка."
    echo "Подробности:"
    eval "$PSQL_RUN -v ON_ERROR_STOP=1 < $SOLUTION_FILE" 2>&1 | grep -i error
    exit 1
fi
