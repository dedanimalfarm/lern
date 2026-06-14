# 02 — Запустить контейнер через runc run

## Задача
Запустить bundle через `runc run` и убедиться в изоляции (свой PID 1, свой
hostname, uid 0). Не забыть `process.terminal=false` для неинтерактивного запуска.

## Проверка
```bash
cd /lab/13/bundle
python3 -c "
import json; d=json.load(open('config.json'))
d['process']['terminal']=False
d['process']['args']=['/bin/sh','-c','echo PID1=\$(cat /proc/1/comm); hostname; id -u']
json.dump(d, open('config.json','w'))
"
runc run demo
runc delete demo 2>/dev/null
```

## Ожидаемый результат
```
PID1=sh        # PID-ns: наш процесс это PID 1
runc           # UTS-ns: hostname контейнера (из config.json)
0              # uid 0 внутри
```
`runc` прочитал `config.json`, поднял namespaces/cgroups/caps и запустил
`process.args` как PID 1. Это и есть `docker run`, только без демона и образов.
