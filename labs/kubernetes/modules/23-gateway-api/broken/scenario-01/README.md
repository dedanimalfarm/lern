# Сценарий 01: Gateway не становится Programmed

## Симптом
```bash
kubectl apply -f broken/scenario-01/gateway.yaml
kubectl -n lab-gateway get gateway broken-gw
# NAME        CLASS           ADDRESS   PROGRAMMED   AGE
# broken-gw   unknown-class             Unknown      10s   <- ни один контроллер не взял шлюз
```

## Подсказки
1. Кто должен «взять» Gateway в работу и по какому полю он его находит?
2. `kubectl get gatewayclass` — есть ли класс с таким именем и кто его контроллер?
3. Что говорят `status.conditions` самого Gateway?

## Диагностика
```bash
kubectl -n lab-gateway describe gateway broken-gw | grep -A10 Conditions
# Accepted: False / Reason: InvalidParameters или Unknown
# Message: GatewayClass "unknown-class" not found
kubectl get gatewayclass
# NAME   CONTROLLER                                      ACCEPTED
# eg     gateway.envoyproxy.io/gatewayclass-controller   True
```

## Решение
Сослаться на существующий класс `eg` (`solutions/scenario-01/gateway.yaml`) или удалить
сломанный шлюз:
```bash
kubectl apply -f solutions/scenario-01/gateway.yaml
kubectl -n lab-gateway wait --for=condition=Programmed gateway/broken-gw --timeout=120s
kubectl delete -f solutions/scenario-01/gateway.yaml
```

## Профилактика
- `gatewayClassName` — это контракт с администратором: список доступных классов
  (`kubectl get gatewayclass`) должен быть частью документации платформы.
- В CI после `apply` ждать `condition=Programmed`, а не просто успешного создания объекта.
