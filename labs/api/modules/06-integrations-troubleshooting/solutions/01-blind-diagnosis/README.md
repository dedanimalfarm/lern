# Решение: как различить четыре поломки за четыре команды

Дерево диагностики (каждый шаг отсекает варианты):

```bash
# Шаг 1: код и время с таймаутом
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://localhost:8080/api/v1/tickets
echo $?
#   exit=28, код 000      -> SLOW (висит дольше таймаута; ttfb ~15 c)
#   код 500               -> ERROR500
#   код 200               -> поломка в ДАННЫХ или КОНТРАКТЕ, шаги 2-3

# Шаг 2 (если 200): валидируем тело
curl -s --max-time 5 http://localhost:8080/api/v1/tickets | jq . >/dev/null
#   jq: parse error ...   -> BADJSON (тело обрезано; смотрите сырое: curl -s ... | head -c 100)

# Шаг 3 (если 200 и тело парсится): сверяем заголовок
curl -s -D - -o /dev/null --max-time 5 http://localhost:8080/api/v1/tickets | grep -i content-type
#   text/html             -> WRONGCT (тело JSON, заголовок врёт)

# Контроль (любой режим): /health всегда 200 — поломка только на боевом пути
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/health
```

Сводная таблица отличительных признаков:

| Режим | Код | exit curl | jq на тело | Content-Type | Время |
|---|---|---|---|---|---|
| `slow` | (нет за 5 с) | 28 | — | — | >15 с |
| `error500` | 500 | 0 | парсится (`error` объект) | application/json | мс |
| `badjson` | 200 | 0 | **parse error** | application/json | мс |
| `wrongct` | 200 | 0 | парсится | **text/html** | мс |

Мнемоника порядка: **код → тело → заголовки → время** (две команды из
четырёх дают вердикт сразу, остальные различаются на следующем шаге).
