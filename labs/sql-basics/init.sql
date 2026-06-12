-- Пересоздаем базу данных
DROP DATABASE IF EXISTS shop_db;
CREATE DATABASE shop_db;

\c shop_db

-- Таблица пользователей
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    registration_date DATE DEFAULT CURRENT_DATE
);

-- Таблица товаров
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT NOT NULL
);

-- Таблица заказов
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'NEW'
);

-- Таблица позиций заказа
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    price_per_unit DECIMAL(10, 2) NOT NULL
);

-- Вставка тестовых данных
INSERT INTO users (name, email, registration_date) VALUES 
('Иван Иванов', 'ivan@example.com', '2023-01-15'),
('Мария Смирнова', 'maria@example.com', '2023-02-20'),
('Петр Петров', 'petr@example.com', '2023-03-05'),
('Анна Сидорова', 'anna@example.com', '2023-03-10');

INSERT INTO products (name, category, price, stock_quantity) VALUES 
('Ноутбук Dell XPS', 'Электроника', 120000.00, 10),
('Смартфон iPhone 14', 'Электроника', 95000.00, 25),
('Наушники Sony WH-1000XM4', 'Аксессуары', 25000.00, 50),
('Мышь Logitech MX Master 3', 'Аксессуары', 8500.00, 100),
('Коврик для мыши', 'Аксессуары', 1200.00, 200),
('Монитор LG 27"', 'Электроника', 35000.00, 15);

INSERT INTO orders (user_id, order_date, status) VALUES 
(1, '2023-04-01 10:30:00', 'COMPLETED'),
(1, '2023-04-15 14:20:00', 'COMPLETED'),
(2, '2023-04-10 09:15:00', 'COMPLETED'),
(3, '2023-04-20 18:45:00', 'NEW'),
(4, '2023-04-22 11:00:00', 'CANCELLED');

INSERT INTO order_items (order_id, product_id, quantity, price_per_unit) VALUES 
(1, 1, 1, 120000.00),
(1, 4, 1, 8500.00),
(2, 3, 1, 25000.00),
(3, 2, 1, 95000.00),
(3, 5, 2, 1200.00),
(4, 6, 2, 35000.00),
(5, 1, 1, 120000.00);
