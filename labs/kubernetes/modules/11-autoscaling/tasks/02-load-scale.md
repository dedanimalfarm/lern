# 02-load-scale

## Задача
Сгенерировать CPU-нагрузку и увидеть scale-up, затем scale-down.

## Команды
```bash
# генератор нагрузки (бьёт по сервису в цикле)
kubectl -n lab run load --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://hpa-demo; done'

kubectl -n lab get hpa hpa-demo -w     # REPLICAS растут до maxReplicas

# убрать нагрузку — через ~стабилизационное окно реплики уменьшатся
kubectl -n lab delete pod load
```

## Проверка
- Под нагрузкой REPLICAS увеличиваются (до 5), после снятия — возвращаются к 1.
