# 02 — Табличная выгрузка открытых тикетов

## Задача
Выгрузить все ОТКРЫТЫЕ тикеты в `/tmp/api-lab/m02-open.tsv`:
колонки `id`, `priority`, `title`, разделитель — табуляция.

## Подсказка
Фильтр на сервере (`?status=open&per_page=50`) + `[.id, .priority, .title] | @tsv`
с флагом `-r`.

## Проверка
```bash
column -t -s$'\t' /tmp/api-lab/m02-open.tsv
awk -F'\t' 'NF!=3 {print "битая строка: " NR}' /tmp/api-lab/m02-open.tsv
```

## Ожидаемый результат
Каждая строка — ровно 3 колонки через табуляцию; файл открывается в Excel /
LibreOffice как таблица.
