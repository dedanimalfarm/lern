# 02 — Жизненный цикл тикета (только по документации)

## Задача
1. Создать тикет: в `title` — подстрока `m03`, приоритет — `critical`
   (имя поля и допустимые значения — найдите в `docs/openapi.yaml`).
2. Взять в работу: статус `in_progress`, назначить `assignee` = `support`.
3. Решить: статус `resolved`.

Шаги 2–3 — тем методом, который НЕ сбрасывает остальные поля
(каким — тоже сказано в доке).

## Проверка
```bash
curl -s 'http://localhost:8080/api/v1/tickets?q=m03' \
  | jq '.items[0] | {status, priority, assignee}'
```

## Ожидаемый результат
`{"status":"resolved","priority":"critical","assignee":"support"}`
