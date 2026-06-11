# 01 — Сводный отчёт смены

## Задача
Из `GET /api/v1/tickets?per_page=50` собрать jq'ом файл
`/tmp/api-lab/m02-report.json` ровно такой структуры:

```json
{
  "total": 8,
  "by_status": {"open": 4, "in_progress": 2, "resolved": 1, "closed": 1},
  "critical_titles": ["Ошибка 500 при выгрузке отчёта из CRM"]
}
```

(числа могут отличаться, если вы создавали свои тикеты — это нормально).

## Подсказка
Один jq-фильтр может вернуть объект:
`{total: .total, by_status: (.items | group_by(.status) | ...), critical_titles: [.items[] | select(...) | .title]}`

## Проверка
```bash
python3 -m json.tool /tmp/api-lab/m02-report.json
jq '.by_status, .critical_titles' /tmp/api-lab/m02-report.json
```

## Ожидаемый результат
Файл валиден, содержит ключи `total` (число), `by_status` (объект),
`critical_titles` (массив строк).
