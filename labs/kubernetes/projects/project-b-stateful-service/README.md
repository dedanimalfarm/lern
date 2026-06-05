# project-b-stateful-service

> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 (Core)

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

Цель: stateful-сервис с сохранением данных и регулярным бэкапом.

## Минимальный состав
- StatefulSet (например Redis)
- headless Service
- PVC
- backup CronJob
- requests/limits и PDB (добавляется при необходимости)

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh projects/project-b-stateful-service
```

## Практические задания

Проект сам по себе является большим практическим заданием. Следуйте инструкциям выше.
