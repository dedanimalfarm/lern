# 04-statefulset-basics

## Цель
Понять стабильные имена Pod, headless Service и пер-реплика тома StatefulSet.

## Манифесты
- `manifests/statefulset/svc-headless.yaml` — headless Service `web` (clusterIP: None).
- `manifests/statefulset/sts.yaml` — StatefulSet `web` (2 реплики) с `volumeClaimTemplates`.

## Шаги
```bash
kubectl -n lab apply -f manifests/statefulset/svc-headless.yaml
kubectl -n lab apply -f manifests/statefulset/sts.yaml
kubectl -n lab rollout status statefulset/web --timeout=180s
```

## Проверка
- Имена Pod фиксированы и упорядочены: `web-0`, `web-1` (создаются по очереди).
- Для каждой реплики автоматически создан свой PVC: `data-web-0`, `data-web-1`.
- DNS-имя реплики доступно через headless Service:
  `web-0.web.lab.svc.cluster.local`.

```bash
kubectl -n lab get pods -l app=web -o wide
kubectl -n lab get pvc -l app=web
kubectl -n lab run dns --image=busybox:1.36 --restart=Never -i --rm -- \
  nslookup web-0.web.lab.svc.cluster.local
```
