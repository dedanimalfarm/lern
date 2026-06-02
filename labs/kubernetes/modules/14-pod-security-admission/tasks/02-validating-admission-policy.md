# 02-validating-admission-policy

## Задача
Запретить образы `:latest` через встроенную ValidatingAdmissionPolicy (CEL).

## Команды
```bash
kubectl apply -f manifests/vap-no-latest.yaml
# в namespace lab попытка создать под с :latest должна быть отклонена:
kubectl -n lab run bad --image=nginx:latest --restart=Never
```

## Проверка
- Под с `:latest` отклонён сообщением из политики.
- Под с конкретным тегом (`nginx:1.27-alpine`) проходит.
