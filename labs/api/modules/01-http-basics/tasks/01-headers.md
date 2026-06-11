# 01 — Снять заголовки ответа в файл

## Задача
Сохранить ТОЛЬКО заголовки ответа `GET /api/v1/tickets` в
`/tmp/api-lab/m01-headers.txt`, тело ответа выбросить.
Это базовый приём «приложить доказательства к тикету».

## Проверка
```bash
head -1 /tmp/api-lab/m01-headers.txt     # HTTP/1.1 200 OK
grep -i x-total-count /tmp/api-lab/m01-headers.txt
```

## Ожидаемый результат
Файл существует, первая строка — `HTTP/1.1 200 OK`, в файле есть
заголовок `X-Total-Count`.
