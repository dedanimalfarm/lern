# 03 — Условные запросы (304) и конкурентный доступ (412)

## Часть А: ETag и 304 Not Modified
1. Прочитайте тикет с заголовками, снимите `ETag`.
2. Повторите GET с `If-None-Match: <этот ETag>` — сервер ответит
   `304 Not Modified` без тела.
3. Сохраните доказательство (статус-строку 304) в
   `/tmp/api-lab/m08-etag.txt`.

```bash
ETAG=$(curl -s -i localhost:8080/api/v1/tickets/1 | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
echo "ETag=$ETAG"
curl -s -i -H "If-None-Match: $ETAG" localhost:8080/api/v1/tickets/1 | head -1
```
> Кавычки — часть значения ETag. Передавайте его в `If-None-Match` ровно
> как получили (вместе с кавычками).

## Часть Б: optimistic locking и 412
Сымитируйте «потерю чужой правки» (lost update):
1. Прочитайте тикет, запомните `ETag`.
2. Кто-то другой меняет тикет (просто сделайте PATCH без `If-Match`) —
   `ETag` устаревает.
3. Попробуйте PATCH со СТАРЫМ `If-Match` — получите `412 Precondition Failed`.
4. Сохраните доказательство (412) в `/tmp/api-lab/m08-concurrency.txt`.

```bash
OLD=$(curl -s -i localhost:8080/api/v1/tickets/2 | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
curl -s -o /dev/null -X PATCH localhost:8080/api/v1/tickets/2 \
  -H 'Content-Type: application/json' -d '{"priority":"high"}'      # «чужая» правка
curl -s -i -X PATCH localhost:8080/api/v1/tickets/2 \
  -H "If-Match: $OLD" -H 'Content-Type: application/json' \
  -d '{"priority":"low"}' | head -1                                 # 412
```

## Проверка
```bash
grep 304 /tmp/api-lab/m08-etag.txt
grep 412 /tmp/api-lab/m08-concurrency.txt
```

## Ожидаемый результат
`m08-etag.txt` содержит `304`, `m08-concurrency.txt` — `412`.
