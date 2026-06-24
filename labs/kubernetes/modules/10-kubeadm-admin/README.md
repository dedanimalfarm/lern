# Лабораторная работа 10: Администрирование kubeadm-кластера

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Обслуживание ноды — cordon / drain / uncordon](#часть-1-обслуживание-ноды--cordon--drain--uncordon)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью)
  - [1.1 cordon: мягкая блокировка новых Pods](#11-cordon-мягкая-блокировка-новых-pods)
  - [1.2 drain: безопасное выселение и PodDisruptionBudget](#12-drain-безопасное-выселение-и-poddisruptionbudget)
  - [1.3 uncordon: возврат ноды в строй](#13-uncordon-возврат-ноды-в-строй)
- [Часть 2: Control-plane как static pods](#часть-2-control-plane-как-static-pods)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [2.1 Анатомия static pods](#21-анатомия-static-pods)
  - [2.2 Редактирование манифестов и перезапуск](#22-редактирование-манифестов-и-перезапуск)
  - [2.3 Mirror pods и их особенности](#23-mirror-pods-и-их-особенности)
- [Часть 3: Сертификаты и kubeconfig](#часть-3-сертификаты-и-kubeconfig)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [3.1 Проверка сроков действия сертификатов](#31-проверка-сроков-действия-сертификатов)
  - [3.2 Продление сертификатов (renew)](#32-продление-сертификатов-renew)
  - [3.3 Перезапуск компонентов после обновления](#33-перезапуск-компонентов-после-обновления)
  - [3.4 Обновление admin.conf и других kubeconfig](#34-обновление-adminconf-и-других-kubeconfig)
- [Часть 4: Бэкап и восстановление etcd](#часть-4-бэкап-и-восстановление-etcd)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [4.1 Создание снапшота базы etcd](#41-создание-снапшота-базы-etcd)
  - [4.2 Восстановление etcd из бэкапа](#42-восстановление-etcd-из-бэкапа)
- [Часть 5: Обновление кластера (kubeadm upgrade)](#часть-5-обновление-кластера-kubeadm-upgrade)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-4)
  - [5.1 Обновление пакетов и kubeadm](#51-обновление-пакетов-и-kubeadm)
  - [5.2 Upgrade control-plane](#52-upgrade-control-plane)
  - [5.3 Upgrade worker нод](#53-upgrade-worker-нод)
- [Часть 6: Добавление и удаление нод](#часть-6-добавление-и-удаление-нод)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-5)
  - [6.1 Генерация токена и команды join](#61-генерация-токена-и-команды-join)
  - [6.2 Удаление ноды и сброс состояния (reset)](#62-удаление-ноды-и-сброс-состояния-reset)
- [Часть 7: Troubleshooting — боевые инциденты](#часть-7-troubleshooting--боевые-инциденты)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-6)
  - [Инцидент 1: drain зависает из-за PDB](#инцидент-1-drain-зависает-из-за-pdb)
  - [Инцидент 2: static pod сломан (опечатка в манифесте)](#инцидент-2-static-pod-сломан-опечатка-в-манифесте)
  - [Инцидент 3: Нода NotReady — сертификаты kubelet](#инцидент-3-нода-notready--сертификаты-kubelet)
  - [Инцидент 4: Нода NotReady — Cgroups rассинхрон](#инцидент-4-нода-notready--cgroups-rассинхрон)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Обслуживание](#блок-1-обслуживание)
  - [Блок 2: Control Plane](#блок-2-control-plane)
  - [Блок 3: PKI и безопасность](#блок-3-pki-и-безопасность)
  - [Блок 4: etcd и обновления](#блок-4-etcd-и-обновления)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
<!-- /TOC -->

> ⏱ время ~60 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)

---

Цель всей работы: научиться осознанно управлять жизненным циклом и компонентами
kubeadm-кластера. Вы научитесь безопасно выводить ноды из обслуживания (`cordon`/`drain`),
понимать, как работают компоненты control-plane (в виде `static pods`), ротировать
сертификаты PKI, делать резервные копии `etcd` и обновлять кластер, а также уметь
диагностировать типовые сбои инфраструктурного уровня.

> **Где это работает.** `cordon`/`drain`/`uncordon` и `PodDisruptionBudget` (PDB)
> работают на ЛЮБОМ кластере (в т.ч. GKE, EKS, AKS). А вот доступ к `static pods`
> control-plane, `kubeadm certs`, `/etc/kubernetes/` и `etcd` есть только на
> **self-managed** kubeadm-кластере — managed-провайдеры control-plane прячут.
> Как поднять свой kubeadm-кластер с нуля — см. `setup-guide.md` в этом модуле.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) Рабочий кластер и kubectl, который в него смотрит
#    (флаг --short удалён в kubectl 1.28+ — используем обычный version)
kubectl version
# Client Version: v1.32.3
# Server Version: v1.36.1   <- версия кластера (kubelet нод)
kubectl cluster-info

# 2) Для Части 1 (drain/PDB) достаточно любого кластера с >=1 нодой.
# Для Частей 2-7 (static pods, certs, etcd, upgrade) нужен доступ по SSH на control-plane хост
# с правами root/sudo.

# 3) Удобный алиас на время работы
alias k='kubectl'
```

---

## Стартовая проверка

Убедитесь, что кластер доступен и все ноды находятся в состоянии Ready:

```bash
kubectl get nodes -o wide
# NAME     STATUS   ROLES           AGE   VERSION   INTERNAL-IP   ...
# cp-1     Ready    control-plane   10d   v1.36.1   10.0.0.10     ...
# node-1   Ready    <none>          10d   v1.36.1   10.0.0.11     ...

# Проверка системных подов
kubectl get pods -n kube-system
```

---

## Часть 1: Обслуживание ноды — cordon / drain / uncordon

### Теория для изучения перед частью

- **`cordon`** помечает ноду как `SchedulingDisabled`. Новые поды на неё не планируются,
  но текущие продолжают работать. Это мягкая блокировка.
- **`drain`** = `cordon` + аккуратно ВЫСЕЛЯЕТ поды (через Eviction API), уважая
  `PodDisruptionBudget`. Применяется перед ребутом ОС, обновлением kubelet или заменой железа.
- **`PodDisruptionBudget` (PDB)** задаёт минимум живых реплик (`minAvailable`) или
  максимум недоступных (`maxUnavailable`) для набора подов. Выселение (Eviction),
  нарушающее PDB, ОТКЛОНЯЕТСЯ — `drain` будет ждать восстановления кворума.
- **`uncordon`** снимает метку `SchedulingDisabled` и возвращает ноду в планирование.

**Жизненный цикл `drain` (почему это безопаснее, чем просто удалить ноду/поды):**

```text
kubectl drain NODE:
   1. cordon -> нода получает taint/annotation SchedulingDisabled.
   2. на КАЖДЫЙ под вызывается Eviction API (а не грубый delete!):
        ├─ DaemonSet-под?      -> пропустить (если передан флаг --ignore-daemonsets).
        ├─ нарушит PDB?        -> ОТКАЗ -> drain ЖДЁТ и повторяет попытку.
        └─ PDB позволяет?      -> graceful остановка: SIGTERM -> terminationGracePeriodSeconds -> SIGKILL.
   3. контроллер (Deployment/StatefulSet) видит удаление пода и планирует его на ДРУГОЙ ноде.
   (итог: нода пуста от пользовательских нагрузок -> можно ребутать/обновлять).
```

| Флаг `drain` | Зачем нужен |
|--------------|-------------|
| `--ignore-daemonsets` | Поды DaemonSet нельзя "выселить" навсегда, их контроллер сразу вернёт. Флаг заставляет игнорировать их наличие, иначе drain завершится ошибкой. |
| `--delete-emptydir-data` | Подтвердить ПОТЕРЮ данных в томах emptyDir у выселяемых подов. |
| `--grace-period=N` | Переопределить время на graceful-остановку пода (игнорируя настройки внутри манифеста пода). |
| `--force` | ⚠️ Выселить "ничьи" поды (без контроллера, типа naked Pod). Они НЕ пересоздадутся и пропадут навсегда. |
| `--disable-eviction` | ⚠️ Вызвать delete вместо Eviction API. ИГНОРИРУЕТ PDB (используйте только в аварийных ситуациях). |

---

### 1.1 cordon: мягкая блокировка новых Pods

Сначала научимся просто запрещать планирование.

```bash
# Выберем первую ноду-воркер (или любую ноду, если кластер однонодовый)
NODE=$(kubectl get nodes | grep -v control-plane | grep -v NAME | awk '{print $1}' | head -n 1)
if [ -z "$NODE" ]; then NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); fi

echo "Работаем с нодой: $NODE"

# Помечаем ноду как SchedulingDisabled
kubectl cordon "$NODE"

# Проверяем статус
kubectl get node "$NODE"
# STATUS: Ready,SchedulingDisabled
```

Теперь новые поды сюда не попадут, но старые продолжают работать.

### 1.2 drain: безопасное выселение и PodDisruptionBudget

Подготовим Deployment и PDB для теста выселения:

```yaml
# manifests/drain-demo.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drain-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: drain-demo
  template:
    metadata:
      labels:
        app: drain-demo
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: drain-demo-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: drain-demo
```

```bash
kubectl apply -f manifests/drain-demo.yaml
kubectl rollout status deploy/drain-demo --timeout=60s

# Смотрим, где запустились поды
kubectl get pods -l app=drain-demo -o wide
```

Теперь запускаем выселение:

```bash
# Выполняем drain (потребуются флаги)
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=60s
# Вывод покажет:
# node/... cordoned
# evicting pod default/drain-demo-...
# pod/drain-demo-... evicted
```

Поскольку у нас 3 реплики и `minAvailable: 2`, выселение 1-2 подов с нашей ноды пройдет успешно. Остальные ноды примут нагрузку.

### 1.3 uncordon: возврат ноды в строй

После проведения технического обслуживания (например, `apt upgrade && reboot`) возвращаем ноду в работу:

```bash
kubectl uncordon "$NODE"
# node/... uncordoned

kubectl get nodes "$NODE"
# STATUS: Ready (без SchedulingDisabled)
```

**Контрольные вопросы:**
1. Чем отличается `cordon` от `drain`? В каком случае достаточно только `cordon`?
2. Почему команда `drain` часто требует флага `--ignore-daemonsets`?
3. Какова роль `PodDisruptionBudget` при выполнении drain?

---

## Часть 2: Control-plane как static pods

### Теория для изучения перед частью

В архитектуре kubeadm ключевые компоненты control-plane (`kube-apiserver`,
`kube-scheduler`, `kube-controller-manager`, а при stacked-топологии и `etcd`)
запускаются как **static pods**.
Их манифесты физически лежат в директории `/etc/kubernetes/manifests/` на control-plane нодах.

`kubelet` регулярно сканирует эту директорию. Если находит файл — он **напрямую** запускает контейнер. Ему не нужен scheduler и не нужен apiserver.

> **Реальность нашего стенда (Kubespray).** Kubespray по умолчанию разворачивает
> etcd как отдельный **systemd-сервис** на хосте (`systemctl status etcd`), а не как
> static pod. Поэтому в `/etc/kubernetes/manifests/` на нашем стенде лежат ТОЛЬКО три
> файла (`kube-apiserver.yaml`, `kube-controller-manager.yaml`, `kube-scheduler.yaml`),
> а пода `etcd-*` в `kube-system` нет. На «ванильном» kubeadm со stacked-etcd там был бы
> и `etcd.yaml` (и mirror-pod `etcd-<node>`). Концепция static pods от этого не меняется —
> просто etcd на Kubespray вынесен из неё.

| Характеристика | static pod | обычный pod |
|---|---|---|
| Место определения | Файл в `/etc/kubernetes/manifests/` | Объект в etcd через apiserver |
| Кто запускает | сам `kubelet` (напрямую) | scheduler выбирает ноду, `kubelet` исполняет |
| Как изменить | Изменить файл манифеста на диске | `kubectl edit / apply` |
| Видимость в API | Mirror-pod (read-only отражение) | Полноценный объект Pod |
| Удаление | Удалить файл с диска | `kubectl delete pod` |
| Имя в кластере | `<name>-<nodeName>` (напр. `etcd-cp-1`) | `<name>-<hash>` (напр. `nginx-68f4...`) |

> **Проблема "Курицы и яйца" в Kubernetes:**
> Откуда возьмётся первый `kube-apiserver`, если поды запускает `kubelet` по команде от `apiserver`?
> Решение: **static pods**. Kubelet поднимает основные компоненты ПРЯМО из файлов на диске. Это позволяет control-plane "загрузить сам себя". Когда apiserver стартует, kubelet создает для него read-only запись (mirror pod) в API для удобства мониторинга.

**Схема: как control-plane «загружает сам себя» через static pods:**

```text
   /etc/kubernetes/manifests/*.yaml            (файлы на диске)
            │
            │  kubelet периодически сканирует каталог
            ▼
   kubelet НАПРЯМУЮ запускает контейнеры        (scheduler и apiserver НЕ нужны)
            │   kube-apiserver · kube-controller-manager · kube-scheduler
            │   (+ etcd, если stacked; на Kubespray etcd — systemd, вне этой схемы)
            ▼
   apiserver поднялся → kubelet создаёт mirror pods (read-only) в API:
            kube-apiserver-k8s-cp-1 · kube-controller-manager-k8s-cp-1 · kube-scheduler-k8s-cp-1
            (видны в kubectl get pod -n kube-system)
```

### 2.1 Анатомия static pods

Зайдите по SSH на control-plane ноду и выполните:

```bash
sudo ls /etc/kubernetes/manifests
# На нашем стенде (Kubespray) — три файла:
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
# (etcd.yaml здесь НЕТ — etcd запущен как systemd-сервис: systemctl status etcd.
#  На kubeadm со stacked-etcd в этом каталоге был бы и etcd.yaml.)
```

Посмотрим содержимое `kube-apiserver.yaml`:

```bash
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -A 5 "command:"
# Вы увидите огромный список флагов, передаваемых apiserver:
# - kube-apiserver
# - --advertise-address=...
# - --allow-privileged=true
# - --authorization-mode=Node,RBAC
# - --client-ca-file=/etc/kubernetes/pki/ca.crt
```

### 2.2 Редактирование манифестов и перезапуск

Любое изменение в файле манифеста заставит `kubelet` мгновенно перезапустить этот компонент.

```bash
# Сделаем бэкап манифеста
sudo cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak

# Откроем файл для редактирования (добавим фиктивный лог-левел или аннотацию)
sudo sed -i '/^  labels:/a\    custom-annotation: "tested"' /etc/kubernetes/manifests/kube-scheduler.yaml
```

Kubelet сразу же заметит изменение хеша файла и перезапустит Pod:

```bash
# Смотрим, как Pod пересоздается
crictl ps | grep scheduler
# или
kubectl get pods -n kube-system -w | grep scheduler
```

Вернем все обратно:

```bash
sudo mv /root/kube-scheduler.yaml.bak /etc/kubernetes/manifests/kube-scheduler.yaml
```

### 2.3 Mirror pods и их особенности

```bash
# В API мы видим эти поды
kubectl get pods -n kube-system | grep -E "apiserver|etcd|scheduler|controller"

# Попытка удалить mirror pod ничего не даст
kubectl delete pod -n kube-system kube-apiserver-cp-1
# Вывод скажет, что pod удален, но он МГНОВЕННО появится снова с тем же uptime,
# потому что kubelet просто восстановит mirror-запись, ведь реальный контейнер не умер.
```

**Контрольные вопросы:**
1. Почему static pod нельзя удалить командой `kubectl delete pod`?
2. Какой компонент кластера читает директорию `/etc/kubernetes/manifests`?
3. Что произойдет, если в файле `kube-apiserver.yaml` допустить синтаксическую ошибку (например, сломать YAML отступы)?

---

## Часть 3: Сертификаты и kubeconfig

### Теория для изучения перед частью

Kubeadm автоматически разворачивает полноценную инфраструктуру открытых ключей (PKI) в директории `/etc/kubernetes/pki/`.
Сертификаты используются для:
- Шифрования трафика (TLS).
- Аутентификации компонентов друг с другом (apiserver -> kubelet, apiserver -> etcd).
- Авторизации пользователей (админский kubeconfig использует сертификат, выписанный на `system:masters`).

Срок действия серверных и клиентских сертификатов по умолчанию — **1 год**. Корневой CA (Certificate Authority) живет **10 лет**.
Если сертификаты истекают, кластер полностью "разваливается": `kubectl` перестает работать, ноды становятся `NotReady`, компоненты не могут общаться друг с другом.

| Файл сертификата | Описание | Кем подписан |
|------------------|----------|--------------|
| `ca.crt` / `ca.key` | Корневой сертификат кластера | Self-signed |
| `apiserver.crt` | Сертификат для TLS-сервера apiserver | `ca` |
| `apiserver-kubelet-client.crt` | Для доступа apiserver к kubelet API | `ca` |
| `etcd/ca.crt` | Отдельный CA для etcd кластера | Self-signed |
| `/etc/kubernetes/admin.conf` | Kubeconfig с клиентским сертификатом админа | `ca` |

### 3.1 Проверка сроков действия сертификатов

Инструмент `kubeadm` имеет встроенную утилиту для управления сертификатами.
Выполнять на control-plane ноде:

```bash
sudo kubeadm certs check-expiration
```

Пример вывода:
```text
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 May 30, 2027 12:00 UTC   364d            ca                      no
apiserver                  May 30, 2027 12:00 UTC   364d            ca                      no
apiserver-etcd-client      May 30, 2027 12:00 UTC   364d            etcd-ca                 no
...
```

### 3.2 Продление сертификатов (renew)

Ежегодно (или перед истечением) сертификаты необходимо обновлять.
Также сертификаты автоматически продлеваются при выполнении `kubeadm upgrade`.

Ручное продление (на control-plane ноде):

```bash
# Обновляем все сертификаты, управляемые kubeadm
sudo kubeadm certs renew all

# Можно обновить и точечно
# sudo kubeadm certs renew apiserver
```

### 3.3 Перезапуск компонентов после обновления

Обновление файлов на диске — это полдела. Компоненты (apiserver, controller-manager, scheduler, etcd) держат старые сертификаты в памяти.
Их нужно перезапустить. Так как это static pods, самый простой способ перезапуска — временно убрать манифесты, или перезапустить kubelet.

Но проще: убить контейнеры, kubelet их мгновенно пересоздаст:

```bash
# Находим контейнеры control-plane
sudo crictl ps | grep -E "kube-apiserver|kube-controller-manager|kube-scheduler|etcd"

# Убиваем их (замените IDs на ваши)
# sudo crictl rm -f <container_id>
```
Или, элегантный трюк — обновить время изменения файлов манифестов:
```bash
sudo touch /etc/kubernetes/manifests/*.yaml
```

### 3.4 Обновление admin.conf и других kubeconfig

Команда `certs renew all` обновляет и файлы конфигурации.
Если вы используете `/root/.kube/config`, вы должны скопировать обновленный `admin.conf`:

```bash
sudo cp /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config
```

**Контрольные вопросы:**
1. Какой срок действия сертификата корневого CA кластера, а какой — у клиентских сертификатов?
2. Что произойдет, если истечет сертификат `apiserver-kubelet-client`?
3. Зачем нужно пересоздавать static pods после обновления сертификатов в `/etc/kubernetes/pki`?

---

## Часть 4: Бэкап и восстановление etcd

### Теория для изучения перед частью

`etcd` — это сердце Kubernetes. В этой key-value базе хранится **всё** состояние кластера (Deployments, Secrets, ConfigMaps, состояние нод).
Потеря данных `etcd` = потеря всего кластера.

Бэкап etcd — это создание snapshot-файла.
Восстановление etcd — это разворачивание базы из snapshot'а в **новую** директорию и перенастройка `etcd.yaml` на использование этой новой директории.

Инструмент: `etcdctl`. Для взаимодействия с кластером etcd, `etcdctl` требует сертификаты аутентификации.

### 4.1 Создание снапшота базы etcd

Подготовим переменные окружения для `etcdctl` на control-plane ноде:

```bash
export ETCDCTL_API=3
export ETCD_CERTS=/etc/kubernetes/pki/etcd

# Снимаем бэкап
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=$ETCD_CERTS/ca.crt \
  --cert=$ETCD_CERTS/peer.crt \
  --key=$ETCD_CERTS/peer.key \
  snapshot save /root/etcd-backup-$(date +%Y-%m-%d).db
```

Проверяем статус созданного бэкапа:

```bash
sudo ETCDCTL_API=3 etcdctl --write-out=table snapshot status /root/etcd-backup-$(date +%Y-%m-%d).db
# Выведет таблицу с хешем, ревизией и общим размером
```

### 4.2 Восстановление etcd из бэкапа

Допустим, кто-то удалил важный namespace. Как откатиться?

1. Восстанавливаем данные из снапшота в **новую** папку (например, `/var/lib/etcd-restore`):
```bash
BACKUP_FILE=$(ls -t /root/etcd-backup-*.db | head -n 1)

sudo ETCDCTL_API=3 etcdctl snapshot restore "$BACKUP_FILE" \
  --data-dir=/var/lib/etcd-restore \
  --initial-cluster=cp-1=https://127.0.0.1:2380 \
  --initial-advertise-peer-urls=https://127.0.0.1:2380 \
  --name=cp-1
```
*(Здесь `cp-1` — это имя вашего узла etcd, его можно узнать в манифесте `/etc/kubernetes/manifests/etcd.yaml`)*.

2. Указываем etcd использовать новую директорию.
Открываем `/etc/kubernetes/manifests/etcd.yaml` и меняем `hostPath` для тома `etcd-data`:

```yaml
  volumes:
  - hostPath:
      path: /var/lib/etcd-restore    # <--- БЫЛО /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

3. Kubelet автоматически перезапустит etcd с восстановленными данными. Apiserver переподключится, и кластер откатится к состоянию из бэкапа.

**Контрольные вопросы:**
1. Почему etcdctl требует передачи флагов `--cacert`, `--cert`, `--key`?
2. Почему при восстановлении мы указываем `--data-dir=/var/lib/etcd-restore`, а не перезаписываем старую папку напрямую?

---

## Часть 5: Обновление кластера (kubeadm upgrade)

### Теория для изучения перед частью

Kubernetes выпускает минорные релизы трижды в год. Поддержка версии длится около 14 месяцев.
Обновление кластера kubeadm производится строго на **одну минорную версию вверх** (например, `v1.35.x -> v1.36.x`). Перепрыгивать нельзя!

Процесс обновления (High Level):
1. Обновить пакет `kubeadm` на control-plane ноде.
2. Запустить `kubeadm upgrade plan`, затем `kubeadm upgrade apply`.
3. Обновить `kubelet` и `kubectl` на control-plane ноде, перезапустить сервис.
4. Повторить для каждой worker-ноды (`kubeadm upgrade node`).

### 5.1 Обновление пакетов и kubeadm

Для примера, покажем команды для Debian/Ubuntu:

```bash
# Ищем доступные версии:
apt update
apt-cache madison kubeadm | grep 1.36

# Устанавливаем конкретную версию kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.36.1-1.1
sudo apt-mark hold kubeadm
```

### 5.2 Upgrade control-plane

Сначала смотрим план:
```bash
sudo kubeadm upgrade plan
# Покажет текущую версию, доступные версии для апгрейда и какие компоненты будут обновлены
# А также сообщит, что сертификаты будут автоматически продлены!
```

Применяем обновление:
```bash
sudo kubeadm upgrade apply v1.36.1
```

После завершения `kubeadm upgrade apply` обновляем `kubelet` и `kubectl`:
```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.36.1-1.1 kubectl=1.36.1-1.1
sudo apt-mark hold kubelet kubectl

# Обязательно рестарт сервиса
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 5.3 Upgrade worker нод

На каждой worker ноде:
1. Выполняем `kubectl drain <worker-node> --ignore-daemonsets` с управляющей машины.
2. Идем на worker:
```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.36.1-1.1
sudo apt-mark hold kubeadm

# Обновляем конфигурацию ноды
sudo kubeadm upgrade node

# Обновляем kubelet
sudo apt-mark unhold kubelet
sudo apt-get install -y kubelet=1.36.1-1.1
sudo apt-mark hold kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```
3. С управляющей машины возвращаем ноду: `kubectl uncordon <worker-node>`.

**Контрольные вопросы:**
1. Какова правильная последовательность обновления компонентов (kubeadm, kubelet, kubectl) на control-plane?
2. Почему нельзя обновлять кластер с версии 1.34 сразу до 1.36?
3. Что автоматически делает `kubeadm upgrade apply` с сертификатами PKI?

---

## Часть 6: Добавление и удаление нод

### Теория для изучения перед частью

Чтобы добавить новую ноду в кластер, на ней нужно установить `containerd`, `kubelet` и `kubeadm`, а затем выполнить команду `kubeadm join`. Эта команда использует bootstrap-токен и хеш сертификата CA для безопасного подключения.

Bootstrap-токены по умолчанию живут 24 часа. Если вы хотите добавить ноду спустя месяц после создания кластера, старый токен уже истёк.

### 6.1 Генерация токена и команды join

На control-plane ноде сгенерируем новый токен и выведем готовую команду для добавления worker'а:

```bash
sudo kubeadm token create --print-join-command
```

Вывод будет похож на:
```bash
kubeadm join 10.0.0.10:6443 --token abcdef.0123456789abcdef \
        --discovery-token-ca-cert-hash sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

Список активных токенов можно посмотреть так:
```bash
sudo kubeadm token list
```

### 6.2 Удаление ноды и сброс состояния (reset)

Если нода больше не нужна:
1. Сначала безопасно выселяем с неё поды:
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```
2. Удаляем ноду из кластера:
```bash
kubectl delete node <node-name>
```
3. Заходим по SSH на саму удаляемую ноду и сбрасываем состояние kubeadm, чтобы очистить iptables/ipvs правила, CNI интерфейсы и файлы:
```bash
sudo kubeadm reset
# Удаляем остатки CNI
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/cni/
```

**Контрольные вопросы:**
1. Сколько времени живет bootstrap токен, созданный `kubeadm token create` по умолчанию?
2. Зачем нужна команда `kubeadm reset` на самой ноде после ее удаления из кластера?

---

## Часть 7: Troubleshooting — боевые инциденты

### Теория для изучения перед частью

Большинство проблем администрирования кластера сводится к следующим категориям:
- Сбои `kubelet`: рассинхрон cgroups, нехватка памяти/диска, истекшие клиентские сертификаты.
- Сбои `control-plane`: синтаксические ошибки в манифестах `/etc/kubernetes/manifests/`, истекшие серверные сертификаты, падение `etcd` из-за медленных дисков (fsync).
- Сетевые сбои: iptables правила не очистились, конфликты подсетей CNI.

### Инцидент 1: drain зависает из-за PDB

**Симптом:** При выполнении `kubectl drain <node>` команда висит и постоянно пишет `Cannot evict pod as it would violate the pod's disruption budget`.

**Диагностика:**
```bash
# Смотрим, какой под не может выселиться
# Проверяем его PDB
kubectl get pdb -A
kubectl describe pdb <pdb-name> -n <namespace>
```
Если `Allowed disruptions: 0`, значит выселение невозможно. Это бывает, если реплик всего 1 и PDB требует `minAvailable: 1`.

**Решение:**
1. Увеличить количество реплик (scale) Deployment/StatefulSet.
2. Изменить PDB на `maxUnavailable: 1`.
3. В крайнем аварийном случае использовать флаг `--disable-eviction` (но это жесткое удаление, нарушающее SLA приложения).

### Инцидент 2: static pod сломан (опечатка в манифесте)

**Симптом:** apiserver перестал отвечать, `kubectl` пишет `The connection to the server was refused`.

**Диагностика:**
Если `kubectl` мертв, диагностируем на уровне ОС хоста:
```bash
# Проверяем логи kubelet
sudo journalctl -u kubelet -f
# Ищем ошибки парсинга YAML: "Failed to parse kube-apiserver.yaml"

# Проверяем, жив ли контейнер
sudo crictl ps -a | grep apiserver
sudo crictl logs <container_id>
```

**Решение:**
Исправить синтаксис (отступы/флаги) в `/etc/kubernetes/manifests/kube-apiserver.yaml`. Kubelet автоматически поднимет под.

### Инцидент 3: Нода NotReady — сертификаты kubelet

**Симптом:** `kubectl get nodes` показывает статус `NotReady` для узла.

**Диагностика:**
Заходим на проблемный узел:
```bash
sudo journalctl -u kubelet -n 100 | grep -i x509
# Ошибка: "x509: certificate has expired or is not yet valid"
```

**Решение:**
Kubelet обычно умеет ротировать свои сертификаты автоматически (kubelet TLS bootstrapping), но если кластер долго был выключен, автоматика ломается.
Нужно пересоздать сертификаты:
На проблемной ноде:
```bash
sudo rm /var/lib/kubelet/pki/kubelet-client-current.pem
sudo systemctl restart kubelet
```
На control-plane ноде одобрить запрос (CSR):
```bash
kubectl get csr
kubectl certificate approve <csr-name>
```

### Инцидент 4: Нода NotReady — Cgroups rассинхрон

**Симптом:** Нода `NotReady`, контейнеры не создаются.

**Диагностика:**
```bash
sudo journalctl -u kubelet | grep cgroup
# Ошибка: "Failed to create cgroup ... misconfigured cgroup driver"
```
Это происходит, когда `kubelet` использует `systemd` cgroup driver, а `containerd` настроен на `cgroupfs` (или наоборот).

**Решение:**
Привести к единому стандарту (рекомендуется `systemd`).
В `/etc/containerd/config.toml`:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```
Перезапустить:
```bash
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

---

## Проверка модуля

У нас нет готового `verify.sh` для этого расширенного модуля, так как выполнение PDB-тестов и ротация сертификатов зависят от конкретного стенда и времени.
Используйте команды `kubectl get nodes` и `kubeadm certs check-expiration` для самопроверки.

Если ноды `Ready`, сертификаты обновлены, а `drain-demo` переживает `drain` — вы справились!

---

## Финальная карта ресурсов модуля

- **Node/drain**: Изучен жизненный цикл узлов и процесс безопасного обслуживания кластера.
- **Static Pods**: Раскрыта механика запуска control-plane без участия scheduler.
- **PKI**: Освоен мониторинг и продление жизненно важных сертификатов кластера.
- **etcd**: Изучен инструмент `etcdctl` для snapshot бэкапирования и восстановления.
- **Upgrade**: Изучена безопасная процедура обновления кластера (kubeadm -> cp -> worker).

---

## Теоретические вопросы (итоговые)

### Блок 1: Обслуживание
1. В чем архитектурное отличие команд `cordon` и `drain`?
2. Почему DaemonSet поды мешают выполнению команды `drain` по умолчанию?
3. Какова роль PodDisruptionBudget в обеспечении высокой доступности сервиса во время обслуживания узлов?

### Блок 2: Control Plane
4. Что такое Static Pod и как `kubelet` его находит и запускает?
5. Почему мы видим `kube-apiserver` в выводе `kubectl get pods`, хотя он запущен не через apiserver?
6. Как применить изменение конфигурации (например, добавить флаг) к работающему `kube-scheduler`?

### Блок 3: PKI и безопасность
7. Какие последствия ожидают кластер, если истечет сертификат `apiserver.crt`?
8. Как обновить сертификаты с помощью `kubeadm` и какие компоненты необходимо перезапустить после этого?
9. Почему при добавлении новой ноды в старый кластер может потребоваться генерация нового токена с помощью `kubeadm token create`?

### Блок 4: etcd и обновления
10. Каков безопасный путь обновления версий кластера с помощью kubeadm? (От control-plane к workers, по одной минорной версии).
11. Почему для выполнения `etcdctl snapshot` требуются TLS сертификаты?

---

## Чему вы научились

В этом модуле вы овладели ключевыми навыками системного администратора Kubernetes. Вы узнали, как кластер обслуживает сам себя, как обеспечивается криптографическое доверие между его компонентами, и как проводить регламентные работы (drain, upgrade, renew certs), не прерывая работу пользовательских сервисов.

---

## Уборка

Используйте команды для возврата узлов в работу и удаления тестовых ресурсов:

```bash
kubectl uncordon --all
kubectl delete deploy drain-demo
kubectl delete pdb drain-demo-pdb
```

---

## Практические задания (отработка)

1. Проведите успешный `cordon` и `drain` любой worker-ноды, убедитесь, что поды переехали. Верните её с `uncordon`.
2. Найдите директорию `/etc/kubernetes/manifests` на control-plane ноде. Сделайте бэкап `kube-apiserver.yaml`.
3. Проверьте оставшийся срок действия сертификатов кластера с помощью команды `kubeadm certs check-expiration`.
4. Сгенерируйте новый join-токен и выведите команду для присоединения новой ноды.
5. Запустите `kubeadm upgrade plan` и изучите предложенный план обновления.

---

## Шпаргалка

```bash
# === Обслуживание ноды ===
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
kubectl get pdb -A

# === Control-plane и Static Pods ===
sudo ls -l /etc/kubernetes/manifests/
sudo journalctl -u kubelet -f
crictl ps
crictl logs <container-id>

# === Сертификаты PKI ===
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all

# === Генерация токенов ===
sudo kubeadm token list
sudo kubeadm token create --print-join-command

# === etcd Бэкап ===
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  snapshot save /root/etcd-backup.db
```
