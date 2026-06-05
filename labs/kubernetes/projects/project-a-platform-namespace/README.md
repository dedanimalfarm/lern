# project-a-platform-namespace

> ⏱ время ~20 мин · сложность 2/5 · пререквизиты: Трек 1 (Core)

## Предварительные требования

```bash
export KUBECONFIG=/root/.kube/kubespray.conf
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

Цель: собрать минимальный platform namespace с базовой безопасностью и лимитами.

## Минимальный состав
- namespace `platform`
- default deny NetworkPolicy
- ResourceQuota + LimitRange
- ingress для demo app (по желанию)

## Проверка
```bash
kubectl get ns platform
kubectl -n platform get resourcequota,limitrange
kubectl -n platform get networkpolicy
```

## Уборка

Очистите ресурсы после завершения:
```bash
../../scripts/clean/clean-module.sh projects/project-a-platform-namespace
```

## Практические задания

Проект сам по себе является большим практическим заданием. Следуйте инструкциям выше.
