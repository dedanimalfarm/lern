#!/bin/bash
set -e

# Определение даты и имени файла
DATE=$(date +%Y-%m-%d)
BACKUP_FILE="/tmp/pagila_${DATE}.dump"
DB_NAME="pagila"

# Автоопределение метода подключения
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="sudo -u postgres psql -d $DB_NAME"
    PGDUMP_CMD="sudo -u postgres pg_dump -d $DB_NAME"
    PGRESTORE_CMD="sudo -u postgres pg_restore -d $DB_NAME"
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    export PGPASSWORD=secretpassword
    PSQL_CMD="psql -h 127.0.0.1 -U postgres -d $DB_NAME"
    PGDUMP_CMD="pg_dump -h 127.0.0.1 -U postgres -d $DB_NAME"
    PGRESTORE_CMD="pg_restore -h 127.0.0.1 -U postgres -d $DB_NAME"
else
    echo "❌ Не удалось подключиться к БД $DB_NAME"
    exit 1
fi

# 1. Резервное копирование в формате Custom
$PGDUMP_CMD -F c -f "$BACKUP_FILE"

# 2. Имитация сбоя (удаление таблицы film_category)
$PSQL_CMD -c "DROP TABLE IF EXISTS film_category CASCADE;"

# 3. Выборочное восстановление таблицы
$PGRESTORE_CMD -t film_category "$BACKUP_FILE"

# 4. Восстановление представлений (VIEW), удаленных каскадно
$PGRESTORE_CMD --schema-only "$BACKUP_FILE" >/dev/null 2>&1 || true

echo "✅ Резервное копирование и выборочное восстановление успешно завершено!"
