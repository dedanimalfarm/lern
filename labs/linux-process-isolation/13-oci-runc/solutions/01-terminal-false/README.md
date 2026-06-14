# Решение scenario-01: `process.terminal = false`

`runc spec` ставит `process.terminal: true` — runc открывает `/dev/tty`. Без
интерактивного tty (скрипт/CI) это падает. Для неинтерактивного запуска:

```bash
# в config.json:
#   "process": { "terminal": false, ... }
jq '.process.terminal=false' config.json | sponge config.json   # или через python
runc run <id>
```

```bash
sudo 13-oci-runc/broken/scenario-01/make-broken.sh        # terminal=true → /dev/tty error
sudo 13-oci-runc/solutions/01-terminal-false/fix.sh         # terminal=false → runc run OK
```

`terminal=true` оставляют только для интерактивного `runc run` с реальным tty
(аналог `docker run -it`). Для фоновых/скриптовых контейнеров — всегда `false`.
