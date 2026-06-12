# Базовый курс по SQL (SQL Basics)

Этот курс предназначен для изучения основ языка SQL (Structured Query Language). Все практические задания выполняются в СУБД PostgreSQL, но полученные знания применимы к большинству реляционных баз данных (MySQL, SQLite, Oracle и др.).

## 🚀 Подготовка стенда (Инициализация БД)

Для выполнения заданий вам потребуется тестовая база данных "Интернет-магазин" (E-commerce).
В корне этого курса находится файл `init.sql`. Запустите его, чтобы создать таблицы и наполнить их тестовыми данными:

```bash
# Подключаемся под пользователем postgres и запускаем скрипт
sudo -u postgres psql -f init.sql
```

В результате будет создана база данных `shop_db` с таблицами: `users`, `products`, `orders` и `order_items`.

## 📦 Модули

1. [01-basic-select](modules/01-basic-select) — Основы выборки данных (SELECT, WHERE, ORDER BY, LIMIT).
2. [02-joins](modules/02-joins) — Соединение таблиц (INNER JOIN, LEFT JOIN).
3. [03-aggregations](modules/03-aggregations) — Агрегация данных и группировка (COUNT, SUM, AVG, GROUP BY, HAVING).
4. [04-dml](modules/04-dml) — Управление данными (INSERT, UPDATE, DELETE).

## 📂 Структура модуля

- `README.md` — теория;
- `tasks/` — практические задания;
- `solutions/` — эталонные SQL-запросы.
