#!/bin/bash
set -e

# Определение даты и имени файла
DATE=$(date +%Y-%m-%d)
BACKUP_FILE="/tmp/shop_db_${DATE}.dump"
DB_NAME="shop_db"

# Автоопределение метода подключения
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="sudo -u postgres psql -d $DB_NAME"
    PGDUMP_CMD="sudo -u postgres pg_dump -d $DB_NAME"
    PGRESTORE_CMD="sudo -u postgres pg_restore -d $DB_NAME"
elif PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    PSQL_CMD="PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d $DB_NAME"
    PGDUMP_CMD="PGPASSWORD=secretpassword pg_dump -h 127.0.0.1 -U postgres -d $DB_NAME"
    PGRESTORE_CMD="PGPASSWORD=secretpassword pg_restore -h 127.0.0.1 -U postgres -d $DB_NAME"
else
    echo "❌ Не удалось подключиться к БД $DB_NAME"
    exit 1
fi

# 1. Резервное копирование в формате Custom
$PGDUMP_CMD -F c -f "$BACKUP_FILE"

# 2. Имитация сбоя (удаление таблицы order_items)
$PSQL_CMD -c "DROP TABLE IF EXISTS order_items CASCADE;"

# 3. Выборочное восстановление таблицы
$PGRESTORE_CMD -t order_items "$BACKUP_FILE"

echo "✅ Резервное копирование и выборочное восстановление успешно завершено!"
