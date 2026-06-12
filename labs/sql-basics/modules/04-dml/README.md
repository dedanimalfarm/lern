# Модуль 4: Управление данными (DML)

## Теория
Data Manipulation Language (DML) — это часть SQL, отвечающая за манипуляцию данными:
- `INSERT` — добавление новых строк.
- `UPDATE` — изменение существующих строк.
- `DELETE` — удаление строк.

> **Внимание:** Всегда используйте `WHERE` в командах `UPDATE` и `DELETE`! Иначе вы обновите или удалите абсолютно все строки в таблице.

Синтаксис:
```sql
INSERT INTO table (col1, col2) VALUES ('val1', 'val2');
UPDATE table SET col1 = 'new_val' WHERE id = 1;
DELETE FROM table WHERE id = 1;
```

## Задания
Перейдите в директорию `tasks/` для выполнения заданий:
- [Задание 1: Изменение данных](tasks/01-dml.md)
