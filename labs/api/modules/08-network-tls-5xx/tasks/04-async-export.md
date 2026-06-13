# 04 — Длинная операция: 202 Accepted + polling

## Задача
Запросите выгрузку и доведите её до готовности по паттерну «принято →
опрашивай статус», как это устроено в реальных экспортах/отчётах:

1. `POST /api/v1/exports` → ответ `202 Accepted`, в `Location` — адрес
   ресурса статуса, в `Retry-After` — через сколько опрашивать.
2. Опрашивайте `Location`, пока `status` не станет `done`.
3. Сохраните **финальный** (done) ответ статуса в
   `/tmp/api-lab/m08-export.json`.

```bash
LOC=$(curl -s -i -X POST localhost:8080/api/v1/exports \
  -H 'Content-Type: application/json' -d '{"format":"csv"}' \
  | awk -F': ' 'tolower($1)=="location"{print $2}' | tr -d '\r')
echo "status_url=$LOC"
# опрос до готовности
until curl -s "localhost:8080$LOC" | jq -e '.status=="done"' >/dev/null; do
  sleep 1
done
curl -s "localhost:8080$LOC" | tee /tmp/api-lab/m08-export.json | jq .
```

## Проверка
```bash
jq '.status, .download_url' /tmp/api-lab/m08-export.json   # "done", "/api/v1/exports/…/download"
```

## Ожидаемый результат
`m08-export.json` — валидный JSON со `status: "done"` и полем
`download_url`. Если вы сохранили ответ со `status: "processing"` —
значит, не дождались готовности (поллинг — это цикл, а не один запрос).
