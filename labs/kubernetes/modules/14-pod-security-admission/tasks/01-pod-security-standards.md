# 01-pod-security-standards

## Задача
Включить Pod Security Admission (restricted) на namespace и проверить отказ.

## Команды
```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl apply -f manifests/good-pod.yaml          # пройдёт
kubectl apply -f broken/scenario-01/bad-pod.yaml  # будет ОТКЛОНЁН
```

## Проверка
- good-pod создан и Running.
- bad-pod отклонён с `violates PodSecurity "restricted"`.
