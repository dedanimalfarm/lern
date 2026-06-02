# 01-define-crd

## Задача
Зарегистрировать собственный тип ресурса WebApp через CRD.

## Команды
```bash
kubectl apply -f manifests/crd.yaml
kubectl get crd webapps.lab.example.com
kubectl api-resources | grep webapp        # появился новый ресурс
```

## Проверка
- `kubectl get webapp` (или `wa`) работает как для встроенных типов.
