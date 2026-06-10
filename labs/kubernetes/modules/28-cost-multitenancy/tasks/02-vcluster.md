# Задание 2: Виртуальные кластеры (vcluster)

vcluster — Kubernetes внутри Kubernetes: в обычном StatefulSet работает
СОБСТВЕННЫЙ API-сервер тенанта (+ kine/SQLite вместо etcd), а syncer
транслирует созданные внутри поды в host-namespace с именами вида
`<pod>-x-<ns>-x-<vcluster>`. Своих нод у vcluster нет.

## Практика

Виртуальный кластер `my-vcluster` уже развернут в namespace `lab` (manifests/01).

```bash
# Извлекаем kubeconfig и направляем его на проброшенный порт
kubectl get secret vc-my-vcluster -n lab -o jsonpath='{.data.config}' | base64 -d \
  | sed 's|server: https://.*|server: https://localhost:18443|' > vcluster.yaml
kubectl -n lab port-forward svc/my-vcluster 18443:443 &

kubectl --kubeconfig vcluster.yaml get namespaces
```

Внутри — только базовые namespace (`default`, `kube-system`, ...), и вы там
полный cluster-admin: можно ставить CRD, создавать namespace, не рискуя
host-кластером.

```bash
kubectl --kubeconfig vcluster.yaml run nginx --image=nginx:1.27-alpine
kubectl --kubeconfig vcluster.yaml get pod nginx -o wide

# А теперь посмотрите на host:
kubectl -n lab get pods
# nginx-x-default-x-my-vcluster   1/1   Running   ...
```

Убедитесь, что host-контракты никуда не делись: посмотрите квоту
`kubectl -n lab describe quota lab-quota` — vcluster и его CoreDNS уже
бронируют её часть, а каждый под тенанта добавляется к used. Что произойдёт,
если тенант запросит больше остатка — см. `broken/scenario-01/`.
