# 03-pdb

## Задача
Защитить доступность при обслуживании ноды через PodDisruptionBudget.

## Команды
```bash
kubectl -n lab apply -f manifests/pdb.yaml
kubectl -n lab get pdb resilient-app-pdb
# ALLOWED DISRUPTIONS = (replicas - minAvailable) = 3 - 2 = 1

# при drain ноды Kubernetes уважает PDB: уведёт максимум 1 реплику за раз
NODE=$(kubectl -n lab get pods -l app=resilient-app -o jsonpath='{.items[0].spec.nodeName}')
# kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --dry-run=server
```

## Проверка
- `ALLOWED DISRUPTIONS = 1` (нельзя увести больше, иначе < minAvailable).
