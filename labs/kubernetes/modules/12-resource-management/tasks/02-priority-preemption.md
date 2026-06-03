# 02 — PriorityClass и preemption

## Задача
Заполнить одну ноду low-prio подами, затем запустить high-prio под и увидеть, как
он ВЫТЕСНЯЕТ (preempt) один low-prio.

## Проверка
```bash
kubectl label node <worker> lab-prio=target --overwrite
kubectl apply -f manifests/priorityclasses.yaml
kubectl -n lab apply -f manifests/low-prio.yaml   # 3x300m заполняют ноду
kubectl -n lab apply -f manifests/high-prio.yaml  # вытеснит один low
kubectl -n lab get events | grep -i preempt
# Уборка: kubectl label node <worker> lab-prio-
```
