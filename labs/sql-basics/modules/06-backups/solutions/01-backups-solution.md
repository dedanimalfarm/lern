# Решение: Задание 1

Выполните следующие команды в терминале операционной системы (или от имени пользователя `postgres` через `sudo`):

```bash
# 1. Создание текстового бэкапа таблицы users
sudo -u postgres pg_dump -d shop_db -t users -F p -f /tmp/users_backup.sql

# 2. Создание бинарного сжатого бэкапа всей базы данных shop_db
sudo -u postgres pg_dump -d shop_db -F c -f /tmp/shop_db.dump

# 3. Симуляция аварии (удаление таблицы order_items)
sudo -u postgres psql -d shop_db -c "DROP TABLE order_items;"

# 4. Выборочное восстановление только таблицы order_items
sudo -u postgres pg_restore -d shop_db -t order_items /tmp/shop_db.dump
```

**Проверка результатов:**
После шага 4 вы можете проверить, что таблица восстановилась и данные на месте, выполнив запрос:
```bash
sudo -u postgres psql -d shop_db -c "SELECT COUNT(*) FROM order_items;"
```
Вывод должен показать количество строк (например, около 400-500 в зависимости от сгенерированных данных).
