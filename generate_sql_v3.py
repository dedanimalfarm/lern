import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

base_dir = "/root/lern/labs/sql-basics/"

# ==============================================================================
# DOCKER-COMPOSE & INIT.SQL
# ==============================================================================
docker_compose = """version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: sql_basics_db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secretpassword
      POSTGRES_DB: shop_db
    ports:
      - "5432:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
"""

init_sql = """-- Структура таблиц
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    registration_date DATE DEFAULT CURRENT_DATE
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT NOT NULL,
    UNIQUE(name)
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'NEW'
);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    price_per_unit DECIMAL(10, 2) NOT NULL
);

-- Генерация данных (100 пользователей)
INSERT INTO users (name, email, registration_date)
SELECT 
    'User_' || i, 
    'user_' || i || CASE WHEN i % 3 = 0 THEN '@gmail.com' ELSE '@example.com' END,
    CURRENT_DATE - (i || ' days')::interval
FROM generate_series(1, 100) i;

-- Генерация данных (50 товаров)
INSERT INTO products (name, category, price, stock_quantity)
SELECT 
    'Product_' || i,
    CASE i % 4 WHEN 0 THEN 'Электроника' WHEN 1 THEN 'Одежда' WHEN 2 THEN 'Книги' ELSE 'Аксессуары' END,
    round((random() * 100000 + 100)::numeric, 2),
    (random() * 100)::int
FROM generate_series(1, 50) i;

-- Генерация данных (200 заказов). Юзеры 81-100 остаются без заказов!
INSERT INTO orders (user_id, order_date, status)
SELECT 
    (random() * 79 + 1)::int, 
    CURRENT_TIMESTAMP - (random() * 30 || ' days')::interval,
    CASE WHEN random() > 0.8 THEN 'CANCELLED' ELSE 'COMPLETED' END
FROM generate_series(1, 200) i;

-- Генерация позиций заказа
INSERT INTO order_items (order_id, product_id, quantity, price_per_unit)
SELECT 
    o.id,
    (random() * 49 + 1)::int,
    (random() * 3 + 1)::int,
    0
FROM orders o, generate_series(1, (random() * 3 + 1)::int) i;

-- Обновление цены
UPDATE order_items oi
SET price_per_unit = p.price
FROM products p
WHERE oi.product_id = p.id;
"""

write_file(os.path.join(base_dir, "docker-compose.yaml"), docker_compose)
write_file(os.path.join(base_dir, "init.sql"), init_sql)

# ==============================================================================
# MODULE 01: SELECT
# ==============================================================================
mod1_task = """# Задание: Основы выборки (01-basic-select)

Напишите SQL-запросы в файл `solution.sql` в этой же папке:

1. Выведите имена (name) и цены (price) **второй десятки** самых дорогих товаров в магазине. (Сортировка по убыванию цены, пропустить первые 10, взять следующие 10).
2. Найдите email-адреса всех пользователей, чья почта заканчивается на `@gmail.com`. Подсказка: используйте `LIKE`.
3. Выведите всех пользователей, которые зарегистрировались в мае (`5`-й месяц) любого года. Подсказка: используйте функцию `EXTRACT(MONTH FROM registration_date)`.
"""

mod1_sol = """-- 1. Пагинация: вторая десятка дорогих товаров
SELECT name, price FROM products 
ORDER BY price DESC 
LIMIT 10 OFFSET 10;

-- 2. Поиск по тексту: пользователи gmail
SELECT email FROM users 
WHERE email LIKE '%@gmail.com';

-- 3. Работа с датами: май
SELECT name, registration_date FROM users 
WHERE EXTRACT(MONTH FROM registration_date) = 5;
"""

mod1_ver = """#!/bin/bash
if [ ! -f "solution.sql" ]; then echo "Файл solution.sql не найден!"; exit 1; fi
PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -f solution.sql > /dev/null 2>&1
if [ $? -eq 0 ]; then echo "PASS: Запросы выполнились без ошибок!"; else echo "FAIL: В запросах синтаксическая ошибка."; fi
"""

write_file(os.path.join(base_dir, "modules/01-basic-select/tasks/01-task.md"), mod1_task)
write_file(os.path.join(base_dir, "modules/01-basic-select/tasks/solution.sql"), mod1_sol)
write_file(os.path.join(base_dir, "modules/01-basic-select/tasks/verify.sh"), mod1_ver)

# ==============================================================================
# MODULE 02: JOINS
# ==============================================================================
mod2_task = """# Задание: Соединения (02-joins)

Напишите SQL-запросы в файл `solution.sql`:

1. Разница LEFT и INNER: Выведите имена всех пользователей (name) и статусы их заказов (status). Если пользователь ничего не заказывал, он всё равно должен быть в списке (вместо статуса будет `NULL`).
2. Классический Anti-Join: Найдите имена пользователей, которые **ни разу** не делали заказ.
3. Соединение множества таблиц: Для заказа с `id = 1` выведите имя пользователя, дату заказа, название купленного товара, количество и итоговую цену позиции (quantity * price_per_unit).
"""

mod2_sol = """-- 1. LEFT JOIN
SELECT users.name, orders.status 
FROM users 
LEFT JOIN orders ON users.id = orders.user_id;

-- 2. Anti-Join (Без заказов)
SELECT users.name 
FROM users 
LEFT JOIN orders ON users.id = orders.user_id 
WHERE orders.id IS NULL;

-- 3. Детализация из 4 таблиц
SELECT 
    u.name, 
    o.order_date, 
    p.name AS product_name, 
    oi.quantity, 
    (oi.quantity * oi.price_per_unit) AS total_item_price
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE o.id = 1;
"""

mod2_ver = """#!/bin/bash
if [ ! -f "solution.sql" ]; then echo "Файл solution.sql не найден!"; exit 1; fi
PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -f solution.sql > /dev/null 2>&1
if [ $? -eq 0 ]; then echo "PASS: Запросы выполнились без ошибок!"; else echo "FAIL: В запросах синтаксическая ошибка."; fi
"""

write_file(os.path.join(base_dir, "modules/02-joins/tasks/01-task.md"), mod2_task)
write_file(os.path.join(base_dir, "modules/02-joins/tasks/solution.sql"), mod2_sol)
write_file(os.path.join(base_dir, "modules/02-joins/tasks/verify.sh"), mod2_ver)

# ==============================================================================
# MODULE 03: AGGREGATIONS
# ==============================================================================
mod3_task = """# Задание: Агрегации (03-aggregations)

Напишите SQL-запросы в файл `solution.sql`:

1. Подсчитайте общую сумму (quantity * price_per_unit) для каждого заказа (order_id) в таблице `order_items`. Выведите `order_id` и `total_sum`.
2. Фильтрация групп (HAVING): Выведите только те `order_id`, общая сумма которых превышает 200 000.
3. MIN / MAX: Выведите дату самого первого (`MIN`) и самого последнего (`MAX`) заказа в магазине (таблица `orders`).
4. Агрегация строк: Соберите названия всех товаров, купленных в заказе с `id = 1`, в одну строку через запятую. Используйте функцию `string_agg(products.name, ', ')`.
"""

mod3_sol = """-- 1. Сумма заказа
SELECT order_id, SUM(quantity * price_per_unit) AS total_sum 
FROM order_items 
GROUP BY order_id;

-- 2. Сумма заказа > 200 000
SELECT order_id, SUM(quantity * price_per_unit) AS total_sum 
FROM order_items 
GROUP BY order_id 
HAVING SUM(quantity * price_per_unit) > 200000;

-- 3. MIN / MAX даты
SELECT MIN(order_date), MAX(order_date) FROM orders;

-- 4. Сборка строк
SELECT string_agg(p.name, ', ') 
FROM order_items oi
JOIN products p ON oi.product_id = p.id
WHERE oi.order_id = 1;
"""

mod3_ver = """#!/bin/bash
if [ ! -f "solution.sql" ]; then echo "Файл solution.sql не найден!"; exit 1; fi
PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -f solution.sql > /dev/null 2>&1
if [ $? -eq 0 ]; then echo "PASS: Запросы выполнились без ошибок!"; else echo "FAIL: В запросах синтаксическая ошибка."; fi
"""

write_file(os.path.join(base_dir, "modules/03-aggregations/tasks/01-task.md"), mod3_task)
write_file(os.path.join(base_dir, "modules/03-aggregations/tasks/solution.sql"), mod3_sol)
write_file(os.path.join(base_dir, "modules/03-aggregations/tasks/verify.sh"), mod3_ver)

# ==============================================================================
# MODULE 04: DML
# ==============================================================================
mod4_task = """# Задание: DML (04-dml)

Напишите SQL-запросы в файл `solution.sql`:

1. Опасность UPDATE: Оберните команду понижения цен на 50% (`price = price * 0.5`) для всех товаров в транзакцию с откатом (`BEGIN; ... ROLLBACK;`).
2. Фишка RETURNING: Добавьте нового пользователя с именем "Тестовый Клиент" и email "test@mail.com" и сразу верните его сгенерированный `id`.
3. UPSERT: У нас есть таблица `products`, где `name` — уникально. Выполните вставку нового товара (name='Флешка', category='Аксессуары', price=1000, stock_quantity=10). Если 'Флешка' уже существует, просто обновите её количество (`stock_quantity = products.stock_quantity + 10`). Используйте `ON CONFLICT (name) DO UPDATE SET ...`.
"""

mod4_sol = """-- 1. Транзакция с откатом
BEGIN;
UPDATE products SET price = price * 0.5;
ROLLBACK;

-- 2. Возврат ID при вставке
INSERT INTO users (name, email) 
VALUES ('Тестовый Клиент', 'test@mail.com') 
RETURNING id;

-- 3. UPSERT
INSERT INTO products (name, category, price, stock_quantity)
VALUES ('Флешка', 'Аксессуары', 1000, 10)
ON CONFLICT (name) DO UPDATE 
SET stock_quantity = products.stock_quantity + EXCLUDED.stock_quantity;
"""

mod4_ver = """#!/bin/bash
if [ ! -f "solution.sql" ]; then echo "Файл solution.sql не найден!"; exit 1; fi
PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -f solution.sql > /dev/null 2>&1
if [ $? -eq 0 ]; then echo "PASS: Запросы выполнились без ошибок!"; else echo "FAIL: В запросах синтаксическая ошибка."; fi
"""

write_file(os.path.join(base_dir, "modules/04-dml/tasks/01-task.md"), mod4_task)
write_file(os.path.join(base_dir, "modules/04-dml/tasks/solution.sql"), mod4_sol)
write_file(os.path.join(base_dir, "modules/04-dml/tasks/verify.sh"), mod4_ver)

for root, dirs, files in os.walk(base_dir):
    for name in files:
        if name.endswith(".sh"):
            os.chmod(os.path.join(root, name), 0o755)

print("SQL Basics modules fully upgraded!")
