# 01 — Провести событие до внешней системы

## Задача
1. Убедиться, что sink поднят и стенд запущен с `WEBHOOK_URL`.
2. Создать тикет с подстрокой `m06` в title.
3. Найти доказательство доставки в ДВУХ местах: журнал приёмника
   (`GET :9100/received`) и лог отправителя (`scripts/api.sh logs`).
4. Сменить статус тикета и убедиться, что пришло событие
   `ticket.status_changed`.

## Проверка
```bash
curl -s http://localhost:9100/received \
  | jq '[.deliveries[].payload | select(.event=="ticket.created")
         | select(.ticket.title | test("m06"))] | length'   # >= 1
```

## Ожидаемый результат
Событие с вашим тикетом есть в журнале приёмника; в логе стенда — строка
`[webhook] ticket.created -> ... 200`.
