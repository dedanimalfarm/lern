# 02-anti-affinity

## Задача
Понять разницу topologySpread и podAntiAffinity.

## Идея
- `topologySpreadConstraints` — про РАВНОМЕРНОСТЬ (maxSkew по доменам).
- `podAntiAffinity` — про «НЕ рядом» (не сажать реплики на одну ноду).
- Часто их комбинируют (как в `manifests/app.yaml`).

## Проверка
```bash
kubectl -n lab get pods -l app=resilient-app \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
# реплики на разных нодах
```
