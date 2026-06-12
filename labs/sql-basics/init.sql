-- Структура таблиц
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
