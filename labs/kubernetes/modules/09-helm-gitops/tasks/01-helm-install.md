# 01 — Helm: lint, install, override, rollback

## Задача
Пройти полный цикл жизни release чарта `demo-app`: проверить чарт, установить, переопределить
values, откатиться на предыдущую ревизию.

## Проверка
```bash
helm lint charts/demo-app
helm template demo charts/demo-app | grep -E '^kind:' | sort | uniq -c
helm upgrade --install demo charts/demo-app -n lab --wait --timeout 120s
helm ls -n lab
kubectl -n lab get deploy,svc,cm,ingress -l app.kubernetes.io/name=demo-app
helm upgrade demo charts/demo-app -n lab --set replicaCount=2 --wait
kubectl -n lab get deploy demo -o jsonpath='{.spec.replicas}'; echo
helm history demo -n lab
helm rollback demo 1 -n lab --wait
kubectl -n lab get deploy demo -o jsonpath='{.spec.replicas}'; echo
helm get values demo -n lab
helm uninstall demo -n lab
```

## Ожидаемый результат
- `helm lint` без ошибок; в рендере — ConfigMap, Deployment, Ingress, Service.
- После install: release `demo` в статусе `deployed`, Deployment `demo` (имя = release name) `1/1`.
- После `--set replicaCount=2` реплик 2, в `helm history` две ревизии; после `rollback 1`
  реплик снова 1, а в истории появилась **третья** ревизия (откат — это новая ревизия,
  а не удаление старой).
- `helm get values` после отката пуст: пользовательские values ревизии 1 не содержали.
