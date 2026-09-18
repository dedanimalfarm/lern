# 01 — Encryption-at-rest: что на самом деле лежит в etcd

## Задача
Убедиться на нашем стенде, что Secret хранится в etcd открытым текстом, и объяснить,
что изменится после включения `--encryption-provider-config` у apiserver.

## Проверка
```bash
kubectl -n lab create secret generic etcd-probe --from-literal=password=SuperSecret123
CP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed -E 's#https://([0-9.]+):.*#\1#')
ssh -i /root/.ssh/kubespray ubuntu@"$CP" 'sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-k8s-cp-1.pem --key=/etc/ssl/etcd/ssl/member-k8s-cp-1-key.pem \
  get /registry/secrets/lab/etcd-probe | strings | grep -iE "SuperSecret|k8s:enc"'
kubectl -n lab delete secret etcd-probe
```

## Ожидаемый результат
- В выводе `etcdctl` видна строка `SuperSecret123` (и её base64 `U3VwZXJTZWNyZXQxMjM=`),
  префикса `k8s:enc:` нет — шифрование в покое на стенде не включено.
- Вы можете назвать флаг apiserver и объект (`EncryptionConfiguration` с провайдером
  `aescbc`/`secretbox`/`kms`), которые это меняют, и объяснить, почему после включения
  уже существующие секреты надо перезаписать
  (`kubectl get secrets -A -o json | kubectl replace -f -`), иначе они так и останутся plaintext.
