# 02-custom-resource

## Задача
Создать экземпляр кастомного ресурса и убедиться в валидации схемой.

## Команды
```bash
kubectl apply -f manifests/webapp.yaml          # валидный
kubectl -n lab get webapp -o wide
kubectl apply -f broken/scenario-01/bad-webapp.yaml   # отклонён схемой
```

## Проверка
- my-webapp создан, виден с колонками Image/Replicas (additionalPrinterColumns).
- bad-webapp отклонён (replicas > 10, нет image).
