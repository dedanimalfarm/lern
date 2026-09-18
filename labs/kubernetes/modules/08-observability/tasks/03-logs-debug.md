# 03-logs-debug

## Задача
Собрать минимальный набор артефактов для инцидента.

## Чеклист
- `logs` проблемного pod
- `describe pod`
- `events`
- `top nodes/pods`
- ingress/service/endpoints состояние
## Проверка
```bash
P=<pod>; D=/tmp/incident-$(date +%s); mkdir -p "$D"
kubectl -n lab logs "$P" --all-containers --previous > "$D/logs-previous.txt" 2>&1 || true
kubectl -n lab logs "$P" --all-containers > "$D/logs.txt"
kubectl -n lab describe pod "$P" > "$D/describe.txt"
kubectl -n lab get events --sort-by=.lastTimestamp > "$D/events.txt"
kubectl top nodes > "$D/top-nodes.txt"; kubectl -n lab top pods > "$D/top-pods.txt"
kubectl -n lab get svc,endpointslices,ingress -o wide > "$D/network.txt"
ls -la "$D"
```

## Ожидаемый результат
- Каталог с семью артефактами; по ним другой инженер без доступа к кластеру может
  назвать симптом, момент деградации и подозреваемый компонент.
- Вы объяснили, зачем `--previous` (логи упавшего контейнера) и почему `describe` и
  `events` надо снимать **до** перезапуска пода.
