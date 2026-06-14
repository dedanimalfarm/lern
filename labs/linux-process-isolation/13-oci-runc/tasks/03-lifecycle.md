# 03 — Жизненный цикл контейнера (create/start/state/delete)

## Задача
Пройти пошаговый жизненный цикл вместо `runc run`: создать контейнер, посмотреть
статус, запустить, удалить — как это делает containerd под Docker.

## Проверка
```bash
cd /lab/13/bundle
runc create demo2
runc state demo2 | python3 -c "import json,sys;d=json.load(sys.stdin);print('status:',d['status'],'pid:',d['pid'])"
runc list
runc start demo2
runc delete --force demo2
```

## Ожидаемый результат
```
status: created pid: <N>      # контейнер создан, процесс ждёт start
ID     PID   STATUS   ...     # runc list показывает demo2
```
`runc create` готовит контейнер (процесс ждёт), `runc start` запускает,
`runc state` отдаёт статус и PID процесса на хосте, `runc delete` убирает. Именно
этим набором containerd-shim управляет контейнером в Docker (`docker run` →
dockerd → containerd → shim → runc).
