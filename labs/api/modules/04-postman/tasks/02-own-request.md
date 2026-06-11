# 02 — Свой запрос с тестами + экспорт

## Задача
1. В папку `10 Tickets CRUD` добавить запрос
   **«Решить тикет (PATCH resolved)»**:
   `PATCH {{base_url}}/api/v1/tickets/{{ticket_id}}`,
   Body raw JSON `{"status": "resolved"}`.
2. Написать минимум два теста: статус 200; `body.status === 'resolved'`.
3. Прогнать цепочку Создать → Взять в работу → Решить.
4. Экспортировать коллекцию (v2.1) в `/tmp/api-lab/m04-collection.json`.

## Проверка
```bash
jq '[.. | objects | select(has("request")) | .name]' /tmp/api-lab/m04-collection.json
curl -s -G http://localhost:8080/api/v1/tickets --data-urlencode 'q=Создано из Postman' \
  | jq -r '.items[-1].status'
```

## Ожидаемый результат
В экспорте 8 запросов (включая ваш с методом PATCH и тестами); последний
тикет «Создано из Postman» в статусе `resolved`.
