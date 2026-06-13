# 02 — Триаж 5xx за балансировщиком

## Задача
Получите от стенда каждый из серверных отказов и запишите в
`/tmp/api-lab/m08-5xx.txt` по строке на код в формате
`<код> <кто ответил и кто «виноват»>`:

- **502** — балансировщик получил от бэкенда мусор/обрыв;
- **503** — сервис жив, но временно отказывает (**обязательно** упомяните
  `Retry-After` — кто его прислал);
- **504** — балансировщик не дождался ответа бэкенда за таймаут.

Как получить каждый:
```bash
for m in error502 error503 error504; do
  curl -s -X POST localhost:8080/api/v1/_lab/fault \
    -H 'Content-Type: application/json' -d "{\"mode\":\"$m\"}" >/dev/null
  echo "=== $m ==="
  curl -s -i localhost:8080/api/v1/tickets | head -8
done
curl -s -X POST localhost:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d '{"mode":"none"}' >/dev/null
```
Обратите внимание на **Content-Type** ответа (наш JSON vs `text/html`
«балансировщика») и на то, у какого кода есть `Retry-After`.

## Проверка
```bash
for c in 502 503 504; do grep -q "^$c " /tmp/api-lab/m08-5xx.txt && echo "$c ok" || echo "$c НЕТ"; done
grep '^503 ' /tmp/api-lab/m08-5xx.txt | grep -i retry-after
```

## Ожидаемый результат
Все три кода с пояснением «кто ответил»; в строке 503 — упоминание
`Retry-After`. Поломка снята (`fault=none`).
