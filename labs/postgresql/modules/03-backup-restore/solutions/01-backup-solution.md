# Решение: Задание 1

```bash
# 1. Создание бэкапа
# Выполнять можно от имени пользователя postgres в системе
sudo -u postgres pg_dump -Fc app_db -f /tmp/app_db_backup.dump

# Проверка, что файл создался
ls -lh /tmp/app_db_backup.dump

# 2. Имитация аварии
sudo -u postgres psql -d app_db -c "DROP TABLE users;"
# Проверка:
sudo -u postgres psql -d app_db -c "\dt" # таблиц нет

# 3. Восстановление
# Флаг -d указывает целевую базу, -1 (единая транзакция, опционально)
sudo -u postgres pg_restore -d app_db /tmp/app_db_backup.dump

# 4. Проверка
sudo -u postgres psql -d app_db -c "SELECT * FROM users;"
```
