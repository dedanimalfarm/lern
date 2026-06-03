# Лабораторная работа 10: Администрирование kubeadm-кластера

Цель: безопасно обслуживать кластер без простоя — выводить ноды из обслуживания
(`cordon`/`drain`), понимать control-plane как static pods, проверять
сертификаты и читать `PodDisruptionBudget`. К концу модуля вы выводите ноду на
обслуживание и возвращаете её, не уронив сервисы.

> **Где это работает.** `cordon`/`drain`/`uncordon` и PDB работают на ЛЮБОМ
> кластере (в т.ч. GKE). А вот доступ к static pods control-plane, `kubeadm certs`
> и `/etc/kubernetes/` есть только на **self-managed** kubeadm-кластере —
> managed-провайдеры (GKE/EKS/AKS) control-plane прячут. Как поднять свой
> kubeadm-кластер с нуля — см. `setup-guide.md` в этом модуле.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl get nodes -o wide
# Для Части 1 (drain/PDB) достаточно любого кластера с >=1 нодой.
# Для Частей 2-3 (static pods, certs) нужен доступ по SSH на control-plane хост.
```

---

## Часть 1: Обслуживание ноды — cordon / drain / uncordon

### Теория для изучения перед частью

- **`cordon`** помечает ноду `SchedulingDisabled` — новые поды на неё не едут,
  но текущие работают.
- **`drain`** = cordon + аккуратно ВЫСЕЛЯЕТ поды (через Eviction API), уважая
  `PodDisruptionBudget`. `--ignore-daemonsets` (их не выселить),
  `--delete-emptydir-data` (подтвердить потерю emptyDir).
- **`PodDisruptionBudget` (PDB)** задаёт минимум живых реплик
  (`minAvailable`) / максимум недоступных (`maxUnavailable`). Eviction,
  нарушающий PDB, ОТКЛОНЯЕТСЯ — `drain` будет ждать.
- **`uncordon`** возвращает ноду в планирование.

---

**Цель:** отработать цикл обслуживания и понять роль PDB.

---

### 1.1 cordon → drain → uncordon

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

kubectl cordon "$NODE"
kubectl get node "$NODE"           # STATUS: Ready,SchedulingDisabled

kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
# evicting pod ...   нода освобождается (DaemonSet-поды остаются)

kubectl uncordon "$NODE"           # вернуть в планирование
```

### 1.2 PDB защищает доступность

```bash
# minAvailable: N не даст drain'у увести реплики ниже N — это защита от
# одновременного выселения всех подов сервиса при обслуживании кластера.
kubectl -n lab get pdb
# NAME             MIN AVAILABLE   ALLOWED DISRUPTIONS
# drain-demo-pdb   1               ...
```

**Контрольные вопросы:**
1. Чем `cordon` отличается от `drain`?
2. Зачем `drain` нужен `--ignore-daemonsets`?
3. Как PDB влияет на `drain` и зачем это нужно при обслуживании кластера?

---

## Часть 2: Control-plane как static pods

### Теория для изучения перед частью

- В kubeadm компоненты control-plane (`kube-apiserver`, `etcd`,
  `kube-scheduler`, `kube-controller-manager`) запускаются как **static pods**:
  их манифесты лежат в `/etc/kubernetes/manifests/`, и `kubelet` поднимает их
  напрямую, без участия scheduler.
- В API они видны как «mirror pods» (read-only отражение). Удалить их через
  `kubectl` нельзя — нужно убрать манифест с диска.

---

**Цель (на kubeadm-хосте):** найти static pods и их источник.

```bash
# На control-plane ноде по SSH:
sudo ls -la /etc/kubernetes/manifests
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

kubectl -n kube-system get pods -o wide | grep -E "apiserver|etcd|scheduler|controller"
# mirror-поды static-компонентов

# Логи (на хосте):
sudo journalctl -u kubelet -n 100 --no-pager
# crictl ps ; crictl logs <id>
```

> На GKE этих файлов нет — control-plane управляется Google и не виден. Часть 2-3
> выполняйте на своём kubeadm-кластере (`setup-guide.md`).

**Контрольные вопросы:**
1. Что такое static pod и чем он отличается от обычного?
2. Почему static pod нельзя удалить через `kubectl delete`?
3. Кто поднимает static pods, если scheduler не участвует?

---

## Часть 3: Сертификаты и kubeconfig

### Теория для изучения перед частью

- kubeadm создаёт PKI в `/etc/kubernetes/pki/` (CA, серверные/клиентские
  сертификаты). Они имеют срок (обычно 1 год) и требуют ротации.
- `kubeadm certs check-expiration` показывает сроки; `kubeadm certs renew`
  обновляет. kubeconfig'и (`/etc/kubernetes/*.conf`) встраивают клиентские сертификаты.

---

**Цель (на kubeadm-хосте):** проверить сроки сертификатов.

```bash
sudo kubeadm certs check-expiration
# CERTIFICATE   EXPIRES   RESIDUAL TIME ...
# apiserver     ...       364d ...
```

**Контрольные вопросы:**
1. Где kubeadm хранит PKI и какой у сертификатов срок по умолчанию?
2. Как проверить и обновить сертификаты?
3. Что встроено в `/etc/kubernetes/admin.conf`?

---

## Часть 4: Troubleshooting

### Инцидент 1: `kubectl drain` зависает — PDB блокирует выселение

Оформлен в `broken/scenario-01/`. `drain-demo` (replicas 1) + PDB
`minAvailable: 1` — выселение единственной реплики нарушило бы PDB.

**Воспроизведение и диагностика:**

```bash
kubectl -n lab apply -f broken/scenario-01/deploy.yaml -f broken/scenario-01/pdb.yaml
# Попытка drain зависнет на эвикте drain-demo:
# kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
#   error when evicting pod "drain-demo-..." : Cannot evict pod as it would
#   violate the pod's disruption budget.
kubectl -n lab describe pdb drain-demo-pdb | grep -E "Allowed disruptions|Min available"
# Min available: 1 ; Allowed disruptions: 0      <- эвикт запрещён
```

**Решение:**

```bash
# Вариант A: PDB по maxUnavailable (готовое решение)
kubectl -n lab apply -f solutions/01-drain-blocked/pdb.yaml   # maxUnavailable: 1
# Вариант B: поднять replicas до 2 (тогда выселение одной не нарушает minAvailable)
kubectl -n lab scale deploy drain-demo --replicas=2
```

**Профилактика:** для сервисов держать >=2 реплик и PDB; одиночные реплики с
`minAvailable:1` делают ноду недренируемой.

**Контрольные вопросы:**
1. Почему `drain` зависает при `minAvailable:1` и `replicas:1`?
2. Два способа разблокировать drain — какие?
3. Что показывает `Allowed disruptions: 0` в PDB?

---

## Проверка модуля

```bash
bash verify/verify.sh
# [OK] module 10 baseline checks passed
```

`verify.sh` — базовые проверки доступности кластера: можно перечислить ноды,
поды `kube-system`, есть `coredns`. Это «дымовой тест» admin-доступа; одна
`[OK]`-строка при успехе.

---

## setup-guide.md — поднять kubeadm-кластер с нуля

Полная инструкция в `setup-guide.md` (1 control-plane + 1 worker на Debian 12):
установка containerd, kubeadm/kubelet/kubectl, `kubeadm init`/`join`, CNI.

> **Важно (исправлено в этом модуле):** в `containerd` `config.toml` параметр
> `SystemdCgroup` должен быть `true` И на control-plane, И на worker. Раньше у
> worker стояло `false` — рассинхрон cgroup-драйвера kubelet/containerd на
> systemd-системе ведёт к нестабильной/`NotReady` ноде.

---

## Финальная карта / итоговые вопросы

| Тема | Команда |
|------|---------|
| Обслуживание ноды | `cordon`/`drain --ignore-daemonsets`/`uncordon` |
| Защита доступности | `PodDisruptionBudget` |
| Control-plane | static pods в `/etc/kubernetes/manifests` |
| Сертификаты | `kubeadm certs check-expiration`/`renew` |

1. Безопасная последовательность вывода ноды на обслуживание?
2. Почему control-plane kubeadm — это static pods?
3. Как PDB защищает сервис при `drain` и когда делает ноду недренируемой?
4. Зачем `SystemdCgroup=true` и что будет при рассинхроне cgroup-драйвера?

---

## Шпаргалка

```bash
# === Обслуживание ноды ===
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
kubectl -n lab get pdb ; kubectl -n lab describe pdb <pdb>

# === Control-plane (на kubeadm-хосте) ===
sudo ls /etc/kubernetes/manifests
sudo journalctl -u kubelet -n 100 --no-pager
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all

# === Уборка ===
kubectl -n lab delete deploy drain-demo --ignore-not-found
kubectl -n lab delete pdb drain-demo-pdb --ignore-not-found
```

---

## Уборка

```bash
kubectl -n lab delete deploy drain-demo --ignore-not-found
kubectl -n lab delete pdb drain-demo-pdb --ignore-not-found
# если меняли реальную ноду — вернуть: kubectl uncordon <node>
```
