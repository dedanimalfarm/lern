# 02 — ApplicationSet порождает Application на окружение

## Задача
Применить ApplicationSet и увидеть, как ОДИН объект создаёт три Argo CD
Application, каждый синхронизирует свой overlay в свой namespace.

## Проверка
```bash
kubectl apply -f applicationset/appproject.yaml
kubectl apply -f applicationset/appset.yaml

# Три Application появились автоматически:
kubectl -n argocd get applications
# web-dev / web-staging / web-prod -> Synced / Healthy

# Развёрнуто по окружениям с разным числом реплик:
for e in dev staging prod; do kubectl -n lab-$e get deploy web; done
# lab-dev 1/1, lab-staging 2/2, lab-prod 3/3
```

## Эксперимент: масштабирование набора
Добавьте в `appset.yaml` элемент `- env: qa` и создайте `overlays/qa` —
ApplicationSet сам создаст `web-qa`. Уберёте элемент — Application удалится
(с `prune` удалятся и его ресурсы).

## Ожидаемый результат
3 Application из одного ApplicationSet, каждый Synced/Healthy, деплои в lab-dev/
staging/prod с репликами 1/2/3.
