# 02-control-plane-staticpods

## Задача
Проверить static pod манифесты и их логи.

## Подсказка
- Манифесты: `/etc/kubernetes/manifests`
- Логи: через `crictl logs` или `journalctl -u kubelet`
## Проверка (на control-plane по SSH)
```bash
ls -la /etc/kubernetes/manifests/
sudo crictl pods --name kube-apiserver
sudo crictl logs $(sudo crictl ps --name kube-apiserver -q) 2>&1 | tail -5
sudo journalctl -u kubelet --since '10 min ago' | tail -20
kubectl -n kube-system get pods -o wide | grep -E 'apiserver|scheduler|controller'
```

## Ожидаемый результат
- В `/etc/kubernetes/manifests/` три файла: `kube-apiserver.yaml`, `kube-scheduler.yaml`,
  `kube-controller-manager.yaml`; `etcd.yaml` **нет** — на Kubespray etcd работает
  systemd-сервисом, а не static pod.
- В `kubectl get pods -n kube-system` эти поды видны с суффиксом имени ноды — это
  «зеркала» (mirror pods), их нельзя удалить через API: kubelet пересоздаст.
- Вы объяснили, что произойдёт, если временно вынести `kube-scheduler.yaml` из каталога,
  и как его логи читать без `kubectl`.
