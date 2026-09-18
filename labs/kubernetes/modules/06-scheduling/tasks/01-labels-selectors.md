# 01-labels-selectors

## Задача
Промаркировать ноды и запланировать deployment через `nodeSelector`.

## Команды
```bash
kubectl label node <node-name> disktype=ssd --overwrite
kubectl -n lab apply -f manifests/selectors/deploy.yaml
```
## Ожидаемый результат
- Все поды deployment'а сели на ноду с меткой `disktype=ssd`
  (`kubectl -n lab get pods -o wide`).
- Если снять метку (`kubectl label node <node-name> disktype-`), уже запущенные поды
  **не** переезжают — nodeSelector проверяется только при планировании; новые поды
  зависнут в `Pending` с `didn't match Pod's node affinity/selector`.
