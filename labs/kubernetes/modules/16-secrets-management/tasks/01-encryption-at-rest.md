# 01 — Encryption-at-rest (etcd)
Проверить, шифруются ли Secret в etcd: прочитать Secret напрямую из etcd (etcdctl по
SSH на control-plane). Виден plaintext -> encryption-provider-config не включён.
