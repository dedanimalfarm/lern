-- 1. Транзакция с откатом
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
