# Сценарий 01: `runc run failed: open /dev/tty` — terminal=true без tty

## Симптом
Собрали bundle, запускаем `runc run` из скрипта — и получаем ошибку про `/dev/tty`.
```bash
sudo ./broken/scenario-01/make-broken.sh
# runc run failed: open /dev/tty: no such device or address
```

## Подсказки
1. Какое значение `process.terminal` ставит `runc spec` по умолчанию?
2. Что делает runc при `terminal=true` (что он пытается открыть)?
3. Есть ли интерактивный tty при запуске из скрипта/CI?

## Диагностика
`runc spec` по умолчанию ставит `process.terminal: true` — runc пытается создать
псевдотерминал и открыть `/dev/tty` управляющего терминала. При запуске без
интерактивного tty (из скрипта, `verify`, CI, через pipe) `/dev/tty` недоступен →
`open /dev/tty: no such device or address`, контейнер не стартует.

## Решение
Выставить `process.terminal=false` в `config.json` (см.
`solutions/01-terminal-false/fix.sh`):
```bash
sudo ./solutions/01-terminal-false/fix.sh
# terminal=false → runc run отрабатывает, вывод процесса идёт в stdout
```

## Профилактика
- Для неинтерактивного запуска (скрипты/CI) всегда `process.terminal=false`.
- `terminal=true` имеет смысл только при `runc run` с реальным tty (или
  `runc exec -t`), как `docker run -it`.
- Быстрая правка: `jq '.process.terminal=false' config.json` или через python.
