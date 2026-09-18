# 03-certs-kubeconfig

## Задача
Понять, какие сертификаты использует control-plane и как проверить срок действия.

## Команда
```bash
sudo kubeadm certs check-expiration
```
## Проверка
```bash
sudo kubeadm certs check-expiration
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates -subject -ext subjectAltName
grep -E 'client-certificate-data|token' /etc/kubernetes/admin.conf | cut -c1-60
```

## Ожидаемый результат
- Таблица `check-expiration` с датами истечения и колонкой `CA`; вы назвали, какой CA
  подписывает `apiserver-kubelet-client` и `front-proxy-client`.
- В SAN серверного сертификата apiserver — имена и IP, включая внутренний IP `k8s-cp-1`;
  внешнего IP там нет — поэтому kubeconfig стенда работает через
  `insecure-skip-tls-verify` (или нужен `--apiserver-cert-extra-sans`).
- Вы знаете, как выглядит продление (`kubeadm certs renew all` + рестарт static pods) и
  почему после него нужно обновить `admin.conf`.
