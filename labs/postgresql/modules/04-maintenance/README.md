# Лабораторная работа 04: Обслуживание базы данных

## Оглавление
- [Часть 1: MVCC и "мертвые" строки](#часть-1-mvcc-и-мертвые-строки)
- [Часть 2: VACUUM и ANALYZE](#часть-2-vacuum-и-analyze)

> ⏱ время ~15 мин · сложность 3/5

Цель: понять, как PostgreSQL управляет версиями строк и зачем нужна очистка.

---

## Часть 1: MVCC и "мертвые" строки

### Теория
При `UPDATE` и `DELETE` строки не удаляются физически, а помечаются как невидимые (dead tuples). Это основа MVCC (Multi-Version Concurrency Control).

---

## Часть 2: VACUUM и ANALYZE

### Практика
```sql
DELETE FROM large_table WHERE id % 2 = 0;
VACUUM VERBOSE large_table;
ANALYZE large_table;
```

---

## Вопросы для самопроверки
1. Почему размер файла таблицы не уменьшается после `VACUUM`?
2. В чем опасность `VACUUM FULL` в production?

👉 **Практика:** Перейдите в папку `tasks/`.
