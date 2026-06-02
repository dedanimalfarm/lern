# 03-cluster-autoscaler

## Задача
Понять связь HPA и Cluster Autoscaler (CA).

## Идея
- HPA добавляет ПОДЫ. Если подам не хватает места на нодах — они в `Pending`.
- Cluster Autoscaler видит `Pending`-поды и добавляет НОДЫ (на управляемых
  кластерах: GKE/EKS с включённым autoscaling node pool).

## Команды (GKE)
```bash
# включить автоскейл node pool (пример)
# gcloud container clusters update lab-cluster --enable-autoscaling \
#   --node-pool lab-cluster-pool --min-nodes 1 --max-nodes 4 --zone us-central1-a

kubectl get events -A | grep -i "TriggeredScaleUp\|NotTriggerScaleUp"
```

## Проверка
- При нехватке ресурсов под `Pending` → событие `TriggeredScaleUp` (если CA включён).
