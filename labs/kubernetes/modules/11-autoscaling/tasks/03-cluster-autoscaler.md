# 03 — Где заканчивается HPA и начинается Cluster Autoscaler

## Задача
Показать границу ответственности: HPA умеет только менять `replicas`. Когда ёмкость
кончается, новые поды не запускаются, и без Cluster Autoscaler (CA) их никто не пристроит.
На стенде Kubespray CA нет — он требует API облака, создающий VM, — поэтому часть про
добавление нод остаётся рассуждением.

## Проверка
```bash
kubectl -n lab apply -k manifests/
kubectl -n lab describe quota lab-quota | grep -E 'requests.cpu|limits.cpu'
kubectl -n lab patch hpa hpa-demo --type=merge -p '{"spec":{"maxReplicas":20}}'
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://hpa-demo >/dev/null; done'
kubectl -n lab get hpa hpa-demo -w
kubectl -n lab get deploy hpa-demo
kubectl -n lab describe rs -l app=hpa-demo | grep -iE 'exceeded quota|FailedCreate' | head -3
kubectl get events -A --field-selector reason=TriggeredScaleUp
kubectl -n lab delete pod load
```

## Ожидаемый результат
- HPA поднимает `desired replicas`, но `READY` у Deployment останавливается ниже:
  на стенде ограничитель — квота namespace, в событиях ReplicaSet `FailedCreate ... exceeded quota`.
- Событий `TriggeredScaleUp` нет — CA отсутствует.
- Вы объяснили, что в облаке с CA ограничитель другой: поды становятся `Pending` с
  `Insufficient cpu`, CA видит их, создаёт VM (событие `TriggeredScaleUp`), нода появляется
  через 1–3 минуты; после снятия нагрузки CA убирает пустую ноду через `scale-down-unneeded-time`
  (по умолчанию 10 минут). Karpenter делает то же без node pool'ов, подбирая размер VM под поды.
