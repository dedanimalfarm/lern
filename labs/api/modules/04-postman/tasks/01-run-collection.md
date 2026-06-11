# 01 — Прогнать коллекцию курса

## Задача
Импортировать `common/postman/helpdesk.postman_collection.json` +
`local.postman_environment.json`, выбрать environment «api-lab local»
и прогнать коллекцию Collection Runner'ом.

## Проверка
В отчёте Runner'а: 7 запросов, 16 проверок, 0 failed.
Дубль-проверка из WSL:
```bash
npx -y newman@6 run common/postman/helpdesk.postman_collection.json \
  -e common/postman/local.postman_environment.json | tail -20
```

## Ожидаемый результат
Все тесты зелёные; в environment появилась переменная `ticket_id`.
