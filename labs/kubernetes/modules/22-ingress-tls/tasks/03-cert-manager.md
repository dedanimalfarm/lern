# 03 — cert-manager (автоматический выпуск)

## Задача
Создать SelfSigned ClusterIssuer и Ingress с аннотацией
cert-manager.io/cluster-issuer — cert-manager сам выпустит cert в Secret.

## Проверка
```bash
kubectl apply -f manifests/cert-manager/clusterissuer.yaml
kubectl -n lab apply -f manifests/cert-manager/ingress-cm.yaml
kubectl -n lab get certificate auto-tls   # READY=True; Secret/auto-tls создан САМ
```
