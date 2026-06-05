# Лабораторная работа 15: NetworkPolicy с реальным enforcement (микросегментация)

> ⏱ время ~25 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

Цель: построить и проверить настоящую сетевую сегментацию `web → api → db` —
где каждый уровень видит только то, что ему положено, а запрещённые пути
по-настоящему блокируются. В отличие от модуля 04 (база), здесь акцент на
**enforcement**: политики реально режут трафик, и мы это доказываем тестами.

> **Требование к среде.** Этот модуль имеет смысл только на кластере с CNI,
> который применяет NetworkPolicy: **Calico / Cilium / GKE Dataplane V2**. Наш
> Kubespray-кластер (Calico) подходит. На managed GKE без Dataplane V2 или голом
> kind политики создаются, но трафик НЕ фильтруется — сегментация будет фикцией.

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab delete deploy,svc,netpol,pod --all --ignore-not-found 2>/dev/null

# КЛЮЧЕВОЕ: убедиться, что CNI умеет enforcement
kubectl -n kube-system get pods | grep -iE "calico|cilium" | head -2 \
  || echo "ВНИМАНИЕ: без calico/cilium NetworkPolicy НЕ будет применяться"
```

---

## Стартовая проверка

```bash
# Калико на всех нодах (по одному calico-node на ноду)
kubectl -n kube-system get pods -l k8s-app=calico-node -o wide 2>/dev/null \
  || kubectl -n kube-system get pods | grep calico-node
```

---

## Часть 1: Модель NetworkPolicy и enforcement

### Теория для изучения перед частью

- По умолчанию связность **разрешена** (default-allow). NetworkPolicy переводит
  выбранные поды в **allow-list**: что не разрешено явно — запрещено.
- **`policyTypes`**: `Ingress` (входящий), `Egress` (исходящий). Важно: чтобы под
  A достучался до B, нужны ОБЕ стороны — egress у A к B И ingress у B от A.
- **Селекторы источников/целей:** `podSelector` (по labels подов),
  `namespaceSelector` (по labels namespace), `ipBlock` (CIDR).
- **Политики аддитивны (OR):** несколько политик на один под — их разрешения
  складываются. Запрета «явного» нет — есть отсутствие разрешения.
- **Enforcement делает CNI**, а не сам Kubernetes. Без поддерживающего CNI объект
  есть, а фильтрации нет.

- **Что CNI делает «под капотом» (Calico).** NetworkPolicy — это лишь ОБЪЕКТ в API.
  `calico-node` (DaemonSet на каждой ноде) ВОТЧИТ их и транслирует в правила
  пакетного фильтра на ноде: `iptables`/`ipset` (стандартный dataplane) или
  **eBPF**-программы (Calico-eBPF / Cilium). `default-deny` = правило «DROP всё, что
  не разрешено явным allow». Пакет от пода проходит через эти правила ДО выхода с
  ноды — поэтому блок реальный, а не «в apiserver».

- **Семантика пустого селектора (частая путаница):**

| Запись | Значит |
|--------|--------|
| `podSelector: {}` | ВСЕ поды namespace (база для default-deny) |
| `podSelector:` отсутствует в `from` | (в правиле) — не ограничивать по подам |
| `from: []` (пустой список) | НИКОГО не пускать (пустой allow) |
| `from:` отсутствует при `policyTypes:[Ingress]` | весь ingress ЗАПРЕЩЁН |

| CNI | Enforcement | Dataplane |
|-----|-------------|-----------|
| Calico | ✅ (наш кластер) | iptables/ipset или eBPF |
| Cilium | ✅ | eBPF (+ L7/FQDN) |
| GKE Dataplane V2 | ✅ | eBPF (Cilium) |
| Flannel / голый kind | ❌ объект есть, трафик НЕ режется | — |

---

**Цель:** убедиться, что default-deny реально закрывает трафик.

---

### 1.1 default-deny действительно режет

```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab rollout status deploy/web --timeout=120s

# ДО политик: любой под ходит куда угодно
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm --labels app=web -- \
  wget -qO- --timeout=4 http://db | grep -i title
# <title>Welcome to nginx!</title>   <- web достучался до db (пока всё открыто)

# Включаем default-deny
kubectl -n lab apply -f manifests/netpol/00-default-deny.yaml
sleep 6

# ПОСЛЕ: тот же запрос блокируется (на Calico — реально)
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm --labels app=web -- \
  wget -qO- --timeout=6 http://db 2>&1 | tail -1
# wget: download timed out  (или под завершается с Error) <- ЗАБЛОКИРОВАНО
```

**Контрольные вопросы:**
1. Что разрешено по умолчанию и что меняет default-deny?
2. Почему для связи A→B нужны и egress у A, и ingress у B?
3. Кто реально применяет NetworkPolicy — Kubernetes или CNI?

---

## Часть 2: Микросегментация web → api → db

### Теория для изучения перед частью

- Классическая 3-уровневая сегментация: **web** принимает извне и ходит в
  **api**; **api** ходит в **db**; **db** не принимает ни от кого, кроме api.
- Порядок включения политик: `default-deny` → `allow-dns` (иначе сломается
  резолв) → правила по уровням.
- Цель — **least privilege на сети**: скомпрометированный web не дотянется до db
  напрямую.

---

**Цель:** собрать сегментацию и проверить матрицу связности.

**Ресурсы:** `manifests/app.yaml` (web/api/db) + `netpol/00..04`.

---

### 2.1 Развернуть сегментацию

```bash
kubectl -n lab apply -f manifests/netpol/    # все 5 политик (00..04)
kubectl -n lab get netpol
# default-deny / allow-dns / web-egress / api-policy / db-policy
```

### 2.2 Тест матрицы связности

```bash
# Хелпер: запрос из пода с заданным label (имитируем уровень)
probe() { kubectl -n lab run p-$RANDOM --labels app=$1 --image=busybox:1.36 \
  --restart=Never -i --rm --timeout=40s -- wget -qO- --timeout=5 http://$2 2>&1 | tail -1; }

probe web api   # OK  (web-egress -> api, api-policy ingress <- web)
probe web db    # БЛОК (у web нет egress к db; db принимает только api)
probe api db    # OK  (api-policy egress -> db, db-policy ingress <- api)
```

| Из \ В | api | db |
|--------|-----|----|
| **web** | ✅ разрешено | 🔒 заблокировано |
| **api** | — | ✅ разрешено |

> Скомпрометированный web физически не дотянется до db — это и есть ценность
> микросегментации.

**Контрольные вопросы:**
1. Почему web→db блокируется, хотя web→api работает?
2. Какие две политики вместе разрешают путь api→db?
3. Как изменить правила, чтобы добавить кэш `cache`, доступный только api?

---

## Часть 3: Egress-контроль и DNS

### Теория для изучения перед частью

- `default-deny` закрывает egress тоже — поэтому **DNS ломается первым**: резолв
  имён идёт к CoreDNS (`kube-system`, `:53`), а это egress.
- Правило: после `default-deny` ВСЕГДА первым добавляют `allow-dns`.
- Egress-политики позволяют ограничить и выход в интернет (разрешить только
  нужные адреса через `ipBlock`).

- **Корректный allow-dns (UDP И TCP :53).** DNS обычно по UDP, но крупные ответы и
  zone-transfer — по TCP, поэтому открывают ОБА протокола. На Kubespray резолвер —
  `nodelocaldns` на link-local `169.254.25.10`, а НЕ под CoreDNS напрямую (см. наш
  `01-allow-dns.yaml`): egress :53 нужен к `ipBlock 169.254.25.10/32` И к поду
  `k8s-app=kube-dns` (для кластеров без nodelocaldns).
- **Egress к ВНЕШНИМ ресурсам.** Прод-приложение часто ходит во внешнюю БД (RDS),
  платёжный API, S3 — это НЕ in-cluster поды, podSelector тут не подходит. Открывают
  egress к их CIDR через `ipBlock` (или, в Cilium/Calico, по FQDN — L7-расширение
  поверх стандартного NetworkPolicy):
  ```yaml
  egress:
  - to: [{ ipBlock: { cidr: 52.0.0.0/11 } }]   # напр. диапазон облачного RDS
    ports: [{ protocol: TCP, port: 5432 }]
  ```

---

### 3.1 Почему allow-dns обязателен

```bash
# Без allow-dns (только default-deny) резолв имён не работает:
kubectl -n lab delete netpol allow-dns 2>/dev/null
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm -- nslookup api 2>&1 | tail -2
# *** Can't find api: ...  / bad address      <- DNS отрезан

kubectl -n lab apply -f manifests/netpol/01-allow-dns.yaml   # вернуть
```

**Контрольные вопросы:**
1. Почему DNS «отваливается» первым при default-deny?
2. Где живёт CoreDNS и какой это тип трафика (ingress/egress) для пода-клиента?
3. Как egress-политикой ограничить выход подов в интернет?

---

## Часть 4: namespaceSelector и ipBlock (расширение)

### Теория для изучения перед частью

- **namespaceSelector** разрешает трафик из ДРУГОГО namespace (например, из
  `monitoring` к метрикам). Комбинируется с podSelector.
- **ipBlock** оперирует CIDR: разрешить подсеть с исключениями (`except`) —
  полезно для доступа к внешним адресам/балансировщикам.

**⚠️ AND vs OR — САМАЯ частая ошибка (разница в ОДНОМ дефисе):**

```yaml
# (1) AND — под app=prometheus И ОДНОВРЕМЕННО в ns monitoring.
#     namespaceSelector и podSelector в ОДНОМ элементе списка (нет дефиса между ними):
from:
- namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } }
  podSelector:       { matchLabels: { app: prometheus } }

# (2) OR — из ЛЮБОГО пода ns monitoring, ИЛИ из пода app=prometheus в ЛЮБОМ ns.
#     ДВА отдельных элемента списка (каждый со своим дефисом):
from:
- namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } }
- podSelector:       { matchLabels: { app: prometheus } }
```

> Один лишний/пропущенный `-` меняет смысл с «строго prometheus-из-monitoring» на
> «вообще весь monitoring + любой prometheus». Это дыра в безопасности №1 при
> написании политик. Правило: элементы СПИСКА `from`/`to` — это **OR**; селекторы
> ВНУТРИ одного элемента — **AND**.

- **`ipBlock`-нюансы:** (а) в одном элементе `ipBlock` НЕЛЬЗЯ совмещать с
  pod/namespaceSelector (ipBlock — отдельный вид источника); (б) для in-cluster
  трафика podSelector надёжнее ipBlock (Pod IP эфемерны); (в) `ipBlock` нужен для
  ВНЕШНИХ адресов (RDS, SaaS-API, link-local nodelocaldns `169.254.25.10/32` для DNS).

```yaml
# Пример: пустить ingress к api ещё и из namespace monitoring (Prometheus):
ingress:
- from:
  - namespaceSelector:
      matchLabels: { kubernetes.io/metadata.name: monitoring }
    podSelector:
      matchLabels: { app: prometheus }
  ports: [{ protocol: TCP, port: 80 }]

# Пример: egress в подсеть, кроме одного диапазона:
egress:
- to:
  - ipBlock:
      cidr: 10.0.0.0/8
      except: ["10.10.0.0/24"]
```

**Контрольные вопросы:**
1. Чем `namespaceSelector` отличается от `podSelector` и когда нужен?
2. Зачем `ipBlock.except` и приведите кейс?
3. Как разрешить доступ к api из namespace `monitoring`, не открывая его всем?

---

## Часть 5: Troubleshooting

### Инцидент 1: default-deny сломал весь namespace (нет allow-dns)

Оформлен в `broken/scenario-01/`. Суть: включили `default-deny` без `allow-dns`
→ во всех подах перестали резолвиться имена (`bad address`). Лечение —
`allow-dns` первым правилом. (Полный разбор — в `broken/scenario-01/README.md`.)

### Инцидент 2: забыли egress-сторону

```bash
# Удалим web-egress -> web перестанет ходить к api, ХОТЯ api-policy ingress это
# разрешает: нет egress-разрешения у источника.
kubectl -n lab delete netpol web-egress
kubectl -n lab run t --labels app=web --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=5 http://api 2>&1 | tail -1
# timed out  <- нужна ОБЕ стороны
kubectl -n lab apply -f manifests/netpol/02-web.yaml
```

### Инцидент 3: «политика не работает»

```bash
# Если запрещённый путь ВСЁ РАВНО проходит — почти всегда CNI без enforcement.
kubectl -n kube-system get pods | grep -iE "calico|cilium" || \
  echo "нет calico/cilium -> политики декоративны (managed GKE без Dataplane V2 / kind)"
```

**Контрольные вопросы:**
1. Симптом «после default-deny всё сломалось» — первая гипотеза и фикс?
2. Путь разрешён ingress'ом цели, но не идёт — что проверить у источника?
3. Запрещённый путь проходит — где причина и как подтвердить?

---

## Проверка модуля

```bash
kubectl -n lab apply -f manifests/app.yaml
kubectl -n lab apply -f manifests/netpol/
kubectl -n lab rollout status deploy/web --timeout=120s
kubectl -n lab rollout status deploy/api --timeout=120s
kubectl -n lab rollout status deploy/db --timeout=120s

bash verify/verify.sh
# [OK] CNI with NetworkPolicy enforcement detected (calico/cilium)
# [OK] module 15 verified
```

`verify.sh` проверяет: namespace `lab` → готовность `web`/`api`/`db` → наличие
всех пяти политик → и предупреждает, если CNI не умеет enforcement (тогда
сегментация декоративна).

---

## Финальная карта (матрица сегментации)

| Источник | → api:80 | → db:80 | DNS:53 |
|----------|----------|---------|--------|
| `web` | ✅ (web-egress + api ingress) | 🔒 | ✅ allow-dns |
| `api` | — | ✅ (api egress + db ingress) | ✅ allow-dns |
| прочие поды ns | 🔒 | 🔒 | ✅ allow-dns |

Политики: `default-deny` (база) + `allow-dns` + `web-egress` + `api-policy` +
`db-policy`.

---

## Теоретические вопросы (итоговые)

1. Объясните allow-list модель NetworkPolicy и роль `default-deny`. Что делает CNI
   (Calico) «под капотом», чтобы политика реально резала трафик?
2. Почему для пути A→B нужны egress у A и ingress у B одновременно?
3. **AND vs OR:** в чём разница между `namespaceSelector`+`podSelector` в ОДНОМ
   элементе `from` и в ДВУХ? Почему это дыра №1?
4. Почему `allow-dns` критичен; почему открывают и UDP, и TCP :53?
5. Чем `podSelector`/`namespaceSelector`/`ipBlock` отличаются? Когда нужен `ipBlock`
   (внешние ресурсы) и почему им не стоит описывать in-cluster трафик?
6. От чего зависит, БУДЕТ ли NetworkPolicy реально применяться?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Постройте матрицу связности web→api→db и подтвердите, что web→db заблокировано, а web→api/api→db — нет.
2. Уберите `allow-dns` и покажите, что резолв ломается под default-deny; верните.
3. Добавьте egress-ограничение для api (только к db:5432) и проверьте, что прочий egress режется.
4. Введите четвёртый ярус и пропишите для него минимально необходимые политики.
5. Проверьте, что под из ЧУЖОГО namespace не достучится до api (namespaceSelector).

---

## Шпаргалка

```bash
# === Применение / обзор ===
kubectl -n lab apply -f manifests/netpol/
kubectl -n lab get netpol
kubectl -n lab describe netpol api-policy

# === Тестирование (probe-поды с label источника) ===
kubectl -n lab run p --labels app=web --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=5 http://db        # ожидаем БЛОК

# === enforcement есть? ===
kubectl -n kube-system get pods | grep -iE "calico|cilium"

# === Уборка ===
kubectl -n lab delete netpol --all      # СНАЧАЛА снять политики
kubectl -n lab delete -f manifests/app.yaml
```

---


## Чему вы научились

В этом модуле вы научились:
- Реализации микросегментации через NetworkPolicy
- Концепции Zero-Trust в кластере (default-deny)
- Разрешению специфичного Ingress/Egress трафика

## Уборка

```bash
kubectl -n lab delete netpol --all          # снять политики первыми
kubectl -n lab delete -f manifests/app.yaml
```
