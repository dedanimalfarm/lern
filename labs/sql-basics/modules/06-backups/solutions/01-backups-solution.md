# Решение: Задание 1

Выполните следующие команды в терминале операционной системы (или от имени пользователя `postgres` через `sudo`):

```bash
# 1. Создание текстового бэкапа таблицы actor
sudo -u postgres pg_dump -d pagila -t actor -F p -f /tmp/actor_backup.sql

# 2. Создание бинарного сжатого бэкапа всей базы данных pagila
sudo -u postgres pg_dump -d pagila -F c -f /tmp/pagila.dump

# 3. Симуляция аварии (удаление таблицы film_category)
sudo -u postgres psql -d pagila -c "DROP TABLE film_category CASCADE;"

# 4. Выборочное восстановление только таблицы film_category
sudo -u postgres pg_restore -d pagila -t film_category /tmp/pagila.dump

# 5. Восстановление каскадно удаленных представлений (VIEW)
sudo -u postgres pg_restore -d pagila --schema-only /tmp/pagila.dump 2>/dev/null || true
```

**Проверка результатов:**
После шага 5 вы можете проверить, что таблица восстановилась и данные на месте, выполнив запрос:
```bash
sudo -u postgres psql -d pagila -c "SELECT COUNT(*) FROM film_category;"
```
Вывод должен показать количество строк (около 1000 в базе данных pagila).
Также убедитесь, что зависимые представления (например, `actor_info`) снова доступны:
```bash
sudo -u postgres psql -d pagila -c "SELECT * FROM actor_info LIMIT 5;"
```
