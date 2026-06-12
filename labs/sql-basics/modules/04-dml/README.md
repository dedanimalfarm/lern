# Лабораторная работа 04: Управление данными (DML)

## Оглавление
- [Часть 1: Вставка данных (INSERT)](#часть-1-вставка-данных)
- [Часть 2: Обновление и Удаление](#часть-2-обновление-и-удаление)
- [Часть 3: Troubleshooting](#часть-3-troubleshooting)

> ⏱ время ~15 мин · сложность 2/5

Цель: научиться изменять данные.

---

## Часть 1: Вставка данных
```sql
INSERT INTO users (name, email) VALUES ('Alex', 'alex@mail.com');
```

---

## Часть 2: Обновление и Удаление
```sql
UPDATE products SET price = price * 0.9 WHERE category = 'Accessories';
DELETE FROM orders WHERE status = 'CANCELLED';
```

---

## Часть 3: Troubleshooting

**Сценарий:** Забыли `WHERE` в запросе `UPDATE` или `DELETE`.
**Урок:** Данные изменятся для ВСЕХ строк таблицы. В production всегда делайте `BEGIN; UPDATE ...; COMMIT;` (или `ROLLBACK;` если ошиблись).

---

## Вопросы для самопроверки
1. Чем `DELETE` отличается от `TRUNCATE`?

👉 **Практика:** Перейдите в папку `tasks/`.
