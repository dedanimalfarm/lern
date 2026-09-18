# Задание 1: LogQL — фильтры и парсеры

Перед началом убедитесь, что стек развернут (`kubectl -n lab get pods`:
loki, promtail, log-generator, payment-api).

Хелпер для запросов из терминала (или используйте Grafana Explore):

```bash
lq() {
  local enc; enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")
  kubectl -n lab exec deploy/loki -- wget -qO- \
    "http://localhost:3100/loki/api/v1/query_range?query=${enc}&limit=${2:-5}&since=5m"
}
```

1. Выберите все логи `payment-api`. Посмотрите на сырые строки — это чистый
   JSON (благодаря stage `cri` в Promtail).
2. Найдите только строки с `"status":500` ДВУМЯ способами: line-фильтром
   (`|= '"status":500'`) и парсером (`| json | status=500`). Чем отличается
   их стоимость и надёжность?
3. Из `log-generator` достаньте `ERROR`-строки про `payment` без слова
   `queued` (сцепка `|=`, `|~ "(?i)..."`, `!=`).
4. Разберите текстовый формат: `| pattern "<ts> <level> <msg> id=<id>"`,
   отфильтруйте `level="WARN"`.
5. Сделайте выдачу читаемой: `| line_format "{{.level}}: {{.msg}} ({{.id}})"`.

<details><summary>Подсказка к п.2</summary>

Line-фильтр — простой grep по подстроке: дёшев, но хрупок (пробел в JSON —
и мимо). Парсер честно разбирает структуру и даёт сравнения чисел
(`status >= 500`), но дороже на больших объёмах. Правило: сначала сузить
line-фильтром, потом парсить: `{...} |= "status" | json | status >= 500`.
</details>
## Ожидаемый результат
- Для каждого из пяти пунктов у вас есть рабочий LogQL-запрос и результат `lq`.
- П.2: оба запроса возвращают одни и те же строки, но вы можете объяснить, когда
  line-фильтр промахнётся (пробел в JSON, `"status": 500`), а парсер — нет.
- П.4–5: строки `WARN` выводятся в формате `WARN: <msg> (<id>)` — `pattern` разобрал
  поля, `line_format` их пересобрал.
