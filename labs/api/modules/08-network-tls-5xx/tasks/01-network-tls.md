# 01 — Сеть ниже HTTP и TLS-сертификат

Две части — слой соединения (до HTTP) и слой шифрования.

## Часть А: каталог curl exit-кодов

Получите руками три сетевых отказа и запишите в `/tmp/api-lab/m08-net.txt`
по строке на код в формате `<exit-код> <чем вызван>`:

- **6** — DNS не резолвится (несуществующий хост);
- **7** — соединение отклонено (порт, который никто не слушает);
- **28** — таймаут (медленный ответ + `--max-time`).

Подсказки (как спровоцировать каждый):
```bash
curl -s -o /dev/null http://no-such-host.invalid/ ; echo "exit=$?"      # 6
curl -s -o /dev/null http://127.0.0.1:9 ; echo "exit=$?"                # 7
# 28: включите медленный режим стенда и поставьте короткий таймаут
curl -s -X POST localhost:8080/api/v1/_lab/fault -H 'Content-Type: application/json' -d '{"mode":"slow"}'
curl -s -o /dev/null --max-time 3 localhost:8080/api/v1/tickets ; echo "exit=$?"   # 28
curl -s -X POST localhost:8080/api/v1/_lab/fault -H 'Content-Type: application/json' -d '{"mode":"none"}'
```

## Часть Б: разбор TLS-сертификата

Поднимите HTTPS-стенд и разберите его сертификат **без** браузера:
```bash
scripts/api.sh tls-up                       # https://127.0.0.1:8443 (самоподпись)
```
В `/tmp/api-lab/m08-tls.txt` соберите:
1. что выдаёт `curl https://127.0.0.1:8443/health` **без** `-k` (код выхода
   и почему);
2. CN сертификата и срок действия (`notAfter`), снятые `openssl s_client`;
3. одну строку: почему «добавить `-k` и забыть» — плохой ответ на инцидент
   с сертификатом.

## Проверка
```bash
for c in 6 7 28; do grep -q "^$c " /tmp/api-lab/m08-net.txt && echo "$c ok" || echo "$c НЕТ"; done
grep -iE 'localhost|notAfter|-k' /tmp/api-lab/m08-tls.txt
```

## Ожидаемый результат
`m08-net.txt` содержит коды 6/7/28 с пояснениями; `m08-tls.txt` — CN
сертификата, срок и формулировку про опасность `-k`. Не забудьте погасить
HTTPS-стенд: `scripts/api.sh tls-down`.
