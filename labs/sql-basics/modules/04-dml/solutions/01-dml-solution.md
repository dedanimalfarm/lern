# Решение: Задание 1

```sql
-- 1. Добавление пользователя
INSERT INTO users (name, email) 
VALUES ('Новый Пользователь', 'new@example.com');

-- 2. Скидка 10% на аксессуары
UPDATE products 
SET price = price * 0.9 
WHERE category = 'Аксессуары';

-- 3. Удаление отмененного заказа (№5)
DELETE FROM orders 
WHERE id = 5;
```
