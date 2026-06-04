# Лабораторная работа 04: Сеть в Kubernetes (Service, DNS, Ingress, NetworkPolicy)

Цель: разобраться, как трафик ходит внутри кластера и попадает в него снаружи —
от Pod IP и `Service` через `Endpoints` и CoreDNS до `NodePort`/`LoadBalancer`/
`Ingress`, и как `NetworkPolicy` ограничивает связность. К концу модуля вы
диагностируете цепочку `Ingress → Service → Endpoints → Pod` и понимаете, почему
«Service есть, а трафик не идёт».

---

## Предварительные требования

```bash
# 0) kubeconfig (наш self-managed кластер развёрнут через Kubespray):
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) Кластер, реально запускающий контейнеры (Kubespray/kind/minikube/k3s/GKE).
#    ВАЖНО для Части 4: enforcement NetworkPolicy есть только при CNI с поддержкой
#    (наш Kubespray — Calico, режет реально; голый kind/managed GKE — нет).
kubectl version --output=yaml | head -5

# 2) Чистый namespace lab (важно: убрать ресурсы прошлых модулей)
kubectl -n lab delete deploy,sts,ds,job,cronjob,svc,pvc,pod,ingress,netpol --all --ignore-not-found
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
```

> **Три важных реальных нюанса этого модуля** (часто бьют новичков):
> - **Ingress** работает только при наличии ingress-controller. Класс `nginx`
>   требует установленного ingress-nginx; на GKE по умолчанию его НЕТ (там свой
>   контроллер класса `gce`). Без контроллера объект Ingress создастся, но адрес
>   не получит.
> - **NetworkPolicy** применяется ТОЛЬКО если CNI это умеет (Calico, Cilium,
>   GKE Dataplane V2). На «голом» GKE/kind без этого политики создаются, но
>   трафик НЕ режут (молча игнорируются).
> - **NodePort/LoadBalancer** в облаке открывают доступ снаружи и могут требовать
>   firewall-правил и стоить денег (облачный LB).

---

## Стартовая проверка

```bash
# CoreDNS — резолвер кластера (Часть 2 на него опирается). ВНИМАНИЕ: имя Service
# отличается по дистрибутивам: kubeadm/kind/GKE — `kube-dns` (legacy-алиас), а
# Kubespray — `coredns`. Поэтому ищем по СТАБИЛЬНОЙ метке k8s-app=kube-dns:
kubectl -n kube-system get svc -l k8s-app=kube-dns
# NAME      TYPE        CLUSTER-IP   PORT(S)
# coredns   ClusterIP   10.233.0.3   53/UDP,53/TCP,9153/TCP   <- адрес DNS кластера
# (на kubeadm/GKE строка была бы `kube-dns ... 10.96.0.10`)

# Какой CNI и умеет ли он NetworkPolicy (важно для Части 4)
kubectl -n kube-system get pods | grep -E "calico|cilium|netd|dataplane" || \
  echo "спец-CNI не найден — NetworkPolicy может НЕ применяться"
```

---

## Часть 1: Service и Endpoints

### Теория для изучения перед частью

- **Pod IP / CNI.** Каждый Pod получает IP от CNI-плагина; модель Kubernetes
  требует прямой Pod-to-Pod связности без NAT. Но Pod IP эфемерны.
- **Service** даёт СТАБИЛЬНЫЙ виртуальный IP (ClusterIP) и DNS-имя. За кулисами
  `kube-proxy` на каждой ноде программирует правила (iptables или IPVS), которые
  балансируют трафик с ClusterIP на реальные Pod.
- **Endpoints / EndpointSlice** — список реальных backend-адресов Service.
  Туда попадают только поды, прошедшие `readinessProbe` и подходящие под
  `selector`. Нет готовых подов под selector — пустой Endpoints — трафик некуда
  слать.
- **Типы Service:** `ClusterIP` (внутри кластера), `NodePort` (порт на каждой
  ноде), `LoadBalancer` (внешний облачный балансировщик), `ExternalName`
  (CNAME на внешний DNS).

**kube-proxy: iptables vs IPVS (важно для масштаба):**

| | iptables (по умолчанию) | IPVS |
|---|---|---|
| Структура | цепочки правил, линейный обход | хеш-таблица |
| Поиск backend | O(n) по числу правил | O(1) |
| Деградация | заметна на ~1000+ Service (минуты на пересборку) | держит десятки тысяч |
| Балансировка | случайная (statistic) | алгоритмы (rr, lc, wrr…) |
| Когда | дефолт, до ~1000 сервисов | большие кластеры |

> ⚠️ **Наш кластер.** Хотя дефолт k8s — iptables, Kubespray ставит `kube-proxy`
> в режиме **`ipvs`** (`kubectl -n kube-system get cm kube-proxy -o yaml | grep mode`
> → `ipvs`). Проверьте на своём — режим виден там же.

> ClusterIP — это НЕ интерфейс и не пингуется: kube-proxy ставит правило DNAT
> (ClusterIP → один из Pod-IP). `ping ClusterIP` = 100% loss, и это норма; проверять
> только `curl` на порт.

- **EndpointSlice (замена Endpoints).** Старый объект `Endpoints` — ОДИН список всех
  адресов сервиса: при 1000 подах любое изменение перезаписывает весь объект (нагрузка
  на etcd/watch). `EndpointSlice` бьёт адреса на куски по ~100 → меняется только
  затронутый срез. С 1.33+ `kubectl get endpoints` печатает deprecation-warning;
  смотреть `kubectl get endpointslices`.
- **`externalTrafficPolicy` (NodePort/LB):** `Cluster` (по умолчанию) — трафик может
  прыгнуть на под на ДРУГОЙ ноде (доп. хоп, source-IP теряется = SNAT);
  `Local` — только локальные поды ноды (сохраняет реальный source-IP, без хопа, но
  трафик на ноду без подов дропается). `sessionAffinity: ClientIP` липнет клиент к
  поду по IP.

---

**Цель:** поднять ClusterIP-сервис и увидеть связь selector → Endpoints.

**Ресурсы:** `manifests/services/` (`net-demo` Deployment×2 + ClusterIP svc).

---

### 1.1 ClusterIP и Endpoints

```bash
kubectl -n lab apply -f manifests/services/
kubectl -n lab rollout status deploy/net-demo --timeout=120s

kubectl -n lab get deploy,svc,endpoints -o wide
# deployment.apps/net-demo   2/2   ...
# service/net-demo   ClusterIP   10.96.x.y   80/TCP   app=net-demo
# endpoints/net-demo   10.20.0.5:80,10.20.1.6:80      <- ОБА пода (Ready) в backend
```

```bash
# Проверим связность изнутри кластера: curl по ClusterIP/имени
kubectl -n lab run probe --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=3 http://net-demo/ | head -1
# <!DOCTYPE html>      <- nginx ответил через Service
```

> EndpointSlice — современная замена Endpoints (масштабируется лучше). На
> кластерах v1.33+ `kubectl get endpoints` даже печатает предупреждение об
> устаревании; смотреть можно `kubectl -n lab get endpointslices`.

### 1.2 Как kube-proxy реализует ClusterIP

```bash
# kube-proxy на каждой ноде; режим (iptables/ipvs) виден в его конфиге/логах
kubectl -n kube-system get ds -l k8s-app=kube-proxy 2>/dev/null | head -2
# ClusterIP не пингуется (это не реальный хост, а правило DNAT в iptables/ipvs):
# ping 10.96.x.y  -> 100% loss, и это НОРМАЛЬНО. Проверять надо curl'ом на порт.
```

### 1.3 Типы Service

| Тип | Где доступен | Как |
|-----|--------------|-----|
| `ClusterIP` | только внутри кластера | виртуальный IP + DNS |
| `NodePort` | снаружи, по `<IP_ноды>:30000-32767` | открывает порт на ВСЕХ нодах |
| `LoadBalancer` | снаружи, по внешнему IP | облачный балансировщик (платно) |
| `ExternalName` | — | CNAME на внешнее DNS-имя, без proxy |

**Контрольные вопросы:**
1. Откуда Pod получает IP и почему на Pod IP нельзя полагаться напрямую?
2. При каком условии IP пода попадает в `Endpoints` сервиса?
3. Почему `ping` по ClusterIP не отвечает, хотя сервис рабочий?
4. Чем `EndpointSlice` лучше `Endpoints`?

---

## Часть 2: DNS в кластере

### Теория для изучения перед частью

- **CoreDNS** (Service `kube-dns` на kubeadm/GKE, `coredns` на Kubespray; метка
  `k8s-app=kube-dns` общая) резолвит имена сервисов:
  `<svc>.<ns>.svc.cluster.local` → ClusterIP.
- **Search domains.** В `/etc/resolv.conf` пода прописаны суффиксы
  (`<ns>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`), поэтому
  внутри namespace достаточно короткого имени `net-demo`.
- **headless Service** (`clusterIP: None`) резолвится не в один VIP, а в адреса
  всех подов (см. StatefulSet в модуле 03).
- **`ndots:5` на числах.** Имя, в котором МЕНЬШЕ 5 точек, сначала перебирается со
  ВСЕМИ search-доменами и лишь потом — как есть. `curl api.example.com` (2 точки <5)
  на нашем кластере делает запросы:
  `api.example.com.lab.svc.cluster.local` → `...svc.cluster.local` →
  `...cluster.local` → … → и только в конце `api.example.com` — **до 6+ DNS-запросов**
  на одно имя (5 промахов + попадание). Для внешних имён ставят ТОЧКУ в конце
  (`api.example.com.` — абсолютное FQDN, 0 лишних запросов) или `dnsConfig.ndots:2`.
- **nodelocaldns (Kubespray).** Чтобы не гонять каждый запрос в CoreDNS-под по сети,
  на каждой ноде стоит кэш `nodelocaldns` на link-local `169.254.25.10:53` — поды
  резолвят через НЕГО (см. `/etc/resolv.conf`: `nameserver 169.254.25.10`). Снижает
  latency и нагрузку на CoreDNS (важно при ndots-«усилении» выше).
- **`dnsPolicy`:** `ClusterFirst` (по умолчанию — сначала кластерный DNS),
  `Default` (наследовать resolv.conf ноды), `None` (+ свой `dnsConfig`).

---

**Цель:** увидеть, как резолвится сервис по полному и короткому имени.

---

### 2.1 Резолв сервиса

```bash
kubectl -n lab run dnscheck --image=busybox:1.36 --restart=Never -i --rm -- \
  nslookup net-demo.lab.svc.cluster.local
# Server:    10.96.0.10
# Name:      net-demo.lab.svc.cluster.local
# Address:   10.96.x.y       <- ClusterIP сервиса net-demo
```

### 2.2 Search domains и короткие имена

```bash
# Изнутри пода в ns lab короткого имени достаточно — сработают search-домены.
# Берём именно успешный ответ через grep (НЕ `tail -3`: busybox-nslookup из-за
# ndots:5 перебирает ВСЕ search-домены, и в хвосте обычно стоят NXDOMAIN от лишних
# доменов — на облачных нодах к ним добавляются ещё и *.internal провайдера).
kubectl -n lab run dnscheck --image=busybox:1.36 --restart=Never -i --rm -- \
  sh -c 'cat /etc/resolv.conf; echo ---; nslookup net-demo 2>&1 | grep -A1 "net-demo.lab.svc"'
# nameserver 169.254.25.10            <- на Kubespray это nodelocaldns (на kubeadm/GKE 10.96.0.10)
# search lab.svc.cluster.local svc.cluster.local cluster.local ...
# options ndots:5
# ---
# Name:    net-demo.lab.svc.cluster.local   <- короткое имя достроилось до FQDN
# Address: 10.233.x.y                        <- ClusterIP сервиса
```

**Контрольные вопросы:**
1. В какой ClusterIP/адреса резолвится `<svc>.<ns>.svc.cluster.local`?
2. Почему внутри namespace работает короткое имя сервиса?
3. Чем DNS headless-сервиса отличается от обычного ClusterIP?
4. Что такое `ndots:5` и какой побочный эффект он даёт для внешних доменов?

---

## Часть 3: Внешний доступ — NodePort, LoadBalancer, Ingress

### Теория для изучения перед частью

- **NodePort** открывает один порт (30000–32767) на КАЖДОЙ ноде; трафик на
  `<нода>:<nodePort>` уходит в Service. В облаке часто нужен firewall-доступ к
  этому порту.
- **LoadBalancer** просит у облака внешний балансировщик с публичным IP, который
  шлёт трафик на NodePort за кулисами. Реальный ресурс — **платный**.
- **Ingress** — L7-роутер: по `host`/`path` направляет HTTP(S) на сервисы.
  Работает только при установленном **ingress-controller**; правило само по себе
  ничего не делает. `ingressClassName` выбирает контроллер (`nginx`, `gce`, …).

**Цепочка LoadBalancer (что под капотом):**

```
интернет → облачный LB (публ. IP, ПЛАТНЫЙ) → :NodePort на ноде → kube-proxy(iptables/ipvs) → Pod
                                                  ▲ LoadBalancer-сервис ВКЛЮЧАЕТ NodePort внутри себя
```
> Поэтому даже LoadBalancer держит NodePort «под капотом». На bare-metal/Kubespray
> облачного LB НЕТ → нужен MetalLB или ingress-nginx baremetal (модуль 22).

- **Ingress vs Gateway API** (Gateway API — преемник Ingress, GA с 1.29):

| | Ingress | Gateway API |
|---|---|---|
| Объекты | один `Ingress` | `GatewayClass` + `Gateway` + `HTTPRoute`/`TCPRoute` |
| Роли | всё в одном (смешаны infra и app) | разделены: оператор кластера (Gateway) vs разработчик (Route) |
| L4/гибкость | в основном HTTP, остальное через аннотации | HTTP/TCP/gRPC/TLS нативно, без аннотаций-«магии» |
| Зрелость | повсеместно, но «застыл» | новый стандарт, развивается |

---

**Цель:** опубликовать сервис наружу тремя способами и понять их различия.

**Ресурсы:** `manifests/nodeport/svc-nodeport.yaml`, `manifests/ingress/ingress.yaml`.

---

### 3.1 NodePort

```bash
kubectl -n lab apply -f manifests/nodeport/svc-nodeport.yaml
kubectl -n lab get svc net-demo-nodeport
# NAME                TYPE       CLUSTER-IP    PORT(S)        AGE
# net-demo-nodeport   NodePort   10.96.x.z     80:30080/TCP   5s
#                                                  ^ внешний порт 30080 на каждой ноде
```

> **На GKE:** порт 30080 на ноде по умолчанию закрыт firewall'ом — для доступа
> снаружи нужно правило:
> `gcloud compute firewall-rules create allow-np --allow tcp:30080`.
> Внутри кластера/через `kubectl` NodePort доступен сразу.

### 3.2 LoadBalancer (реальный внешний IP)

```yaml
# Тип LoadBalancer заставляет облако выдать публичный IP. На GKE это создаёт
# реальный сетевой балансировщик (платный ~$18/мес + трафик) — применяйте
# осознанно и удаляйте после теста.
apiVersion: v1
kind: Service
metadata: { name: net-demo-lb, namespace: lab }
spec:
  type: LoadBalancer
  selector: { app: net-demo }
  ports:
  - { port: 80, targetPort: 80 }
```

```bash
# kubectl -n lab apply -f - <<EOF ... EOF   (манифест выше)
# kubectl -n lab get svc net-demo-lb -w
# EXTERNAL-IP сначала <pending>, через ~1-2 мин — реальный публичный IP:
# net-demo-lb   LoadBalancer   10.96.x.y   34.x.x.x   80:31234/TCP
# curl http://34.x.x.x/   -> ответ nginx из интернета
# Удалить, чтобы не платить:  kubectl -n lab delete svc net-demo-lb
```

### 3.3 Ingress

```bash
kubectl -n lab apply -f manifests/ingress/ingress.yaml
kubectl -n lab get ingress net-demo
# NAME       CLASS   HOSTS            ADDRESS      PORTS
# net-demo   nginx   net-demo.local   10.10.0.4    80     <- ADDRESS = internal-IP ноды (наш ingress-nginx)
```

> ADDRESS появится, ТОЛЬКО если в кластере есть ingress-controller класса `nginx`.
> У нас он установлен (`scripts/bootstrap/03-install-ingress.sh` — ingress-nginx
> baremetal/NodePort с `--report-node-internal-ip-address`), поэтому ADDRESS =
> internal-IP ноды контроллера. На «голом» GKE класс был бы `gce`; без контроллера
> Ingress остаётся без адреса. Проверка маршрутизации (через NodePort контроллера):
> ```bash
> NP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[0].nodePort}')
> # из пода: wget -qO- --header 'Host: net-demo.local' http://ingress-nginx-controller.ingress-nginx/
> # -> Welcome to nginx; чужой Host -> 404 (default backend). Снаружи нужен firewall на NodePort.
> ```

**Контрольные вопросы:**
1. Чем NodePort отличается от LoadBalancer по способу внешнего доступа?
2. Почему объект Ingress без ingress-controller бесполезен?
3. Что делает `ingressClassName` и почему `nginx` ≠ `gce`?
4. Какой диапазон портов у NodePort и на скольких нодах он открывается?

---

## Часть 4: NetworkPolicy

### Теория для изучения перед частью

- По умолчанию в Kubernetes **вся** Pod-to-Pod связность разрешена.
  `NetworkPolicy` переводит выбранные поды в allow-list модель.
- **default-deny** (`podSelector: {}` + оба `policyTypes`) запрещает весь
  ingress и egress для всех подов namespace — основа Zero-Trust. Дальше точечно
  добавляют разрешения.
- **Правила:** `from`/`to` с `podSelector`/`namespaceSelector`/`ipBlock` + порты.
- ⚠️ **Применяется только при поддержке CNI** (Calico, Cilium, GKE Dataplane V2).
  Без неё политики создаются, но не действуют.

---

**Цель:** включить default-deny и поэтапно разрешить DNS и доступ к приложению.

**Ресурсы:** `manifests/netpol/{default-deny,allow-dns,allow-app}.yaml`.

---

### 4.1 default-deny и поэтапные allow

```bash
# Сначала проверим, ЕСТЬ ли enforcement (иначе политики — это no-op):
kubectl -n kube-system get pods | grep -E "calico|cilium|dataplane|netd" \
  || echo "ВНИМАНИЕ: NetworkPolicy скорее всего НЕ применяется на этом кластере"

# Закрыть всё
kubectl -n lab apply -f manifests/netpol/default-deny.yaml
# Разрешить egress к CoreDNS (иначе сломается резолв имён)
kubectl -n lab apply -f manifests/netpol/allow-dns.yaml
# Разрешить доступ к net-demo на :80. ВНИМАНИЕ: это ДВЕ политики (см. файл):
#   allow-app-ingress — ingress К net-demo (открыли дверь у backend);
#   allow-app-egress  — egress ОТ клиента к net-demo (выпустили источник).
# При default-deny на egress одного ingress-правила мало — нужны обе стороны.
kubectl -n lab apply -f manifests/netpol/allow-app.yaml

kubectl -n lab get netpol
# NAME                POD-SELECTOR   AGE
# default-deny        <none>         ...
# allow-dns           <none>         ...
# allow-app-ingress   app=net-demo   ...
# allow-app-egress    <none>         ...
```

> ⚠️ **Среда (nodelocaldns).** На Kubespray (и kubeadm с localdns) включён
> **nodelocaldns** — DNS-кэш на каждой ноде, слушающий link-local `169.254.25.10:53`.
> Поды резолвят имена через НЕГО, а не через под CoreDNS напрямую. Поэтому наш
> `allow-dns.yaml` разрешает egress :53 ДВУМЯ путями: `ipBlock 169.254.25.10/32`
> (nodelocaldns) **и** под `k8s-app=kube-dns` (CoreDNS — для kind/GKE без localdns).
> Если оставить только второе правило — на Kubespray DNS под default-deny останется
> сломанным (`nslookup` → `bad address`), хотя селектор CoreDNS-пода верный.
> Узнать адрес localdns на своём кластере: `kubectl -n kube-system get cm nodelocaldns
> -o yaml | grep -m1 -oE '169\.254\.[0-9.]+'` (или смотрите `__PILLAR__` в Corefile).

### 4.2 Проверка эффекта (если enforcement есть)

```bash
# На кластере С enforcement: до default-deny curl к net-demo из чужого пода идёт
# (всё разрешено), после default-deny — ВИСНЕТ. allow-app возвращает доступ,
# но ТОЛЬКО с обеими политиками (ingress К net-demo + egress ОТ клиента):
kubectl -n lab run t --image=busybox:1.36 --restart=Never -i --rm -- \
  wget -qO- --timeout=4 http://net-demo/ | grep -i title
# default-deny + allow-dns (без allow-app)         -> timeout (egress клиента закрыт);
# + только allow-app-ingress                       -> ВСЁ РАВНО timeout (egress закрыт!);
# + allow-app-ingress И allow-app-egress           -> <title>Welcome to nginx!</title>.
```

> ✅ **Проверено на нашем Kubespray-кластере (Calico), вживую:**
> - до `default-deny` — `<title>Welcome to nginx!</title>`;
> - после `default-deny` (+`allow-dns`) — DNS резолвится (`net-demo` → ClusterIP),
>   но `wget` к net-demo **виснет** (`download timed out`);
> - +`allow-app` (обе политики) — снова `Welcome to nginx!`;
> - убрать ТОЛЬКО `allow-app-egress` — опять `timeout`. Это доказывает: на
>   egress-enforced default-deny поток разрешают **обе** стороны.
>
> ⚠️ **Частая ошибка:** открыть только ingress у backend и удивляться, почему
> клиент всё равно не достучался — у него закрыт собственный egress. Если на
> ВАШЕМ кластере политики вообще НЕ режут трафик — значит CNI без поддержки
> (managed GKE без Dataplane V2, голый kind): объекты создаются, но не действуют.

**Контрольные вопросы:**
1. Что разрешено между подами по умолчанию, до любой NetworkPolicy?
2. Как устроен default-deny и почему он — основа Zero-Trust?
3. Почему при default-deny обязательно нужен явный allow к CoreDNS?
4. От чего зависит, БУДЕТ ли NetworkPolicy реально применяться?
5. Почему при default-deny на egress одного ingress-правила к backend мало?
   Какие ДВЕ политики нужны, чтобы клиент достучался до net-demo?

---

## Часть 5: Troubleshooting — боевые инциденты

### Инцидент 1: Service есть, поды Running, но трафик не идёт (selector mismatch)

Оформлен в `broken/scenario-01/`. Здесь — полный цикл.

**Воспроизведение:**

```bash
kubectl -n lab apply -f broken/scenario-01/deploy.yaml
kubectl -n lab apply -f broken/scenario-01/svc.yaml
sleep 6
```

**Диагностика:**

```bash
# Поды есть и Ready
kubectl -n lab get pods -l app=net-demo --show-labels
# net-demo-...   1/1   Running   app=net-demo,...

# Но Endpoints сервиса ПУСТ
kubectl -n lab get endpoints net-demo
# net-demo   <none>     <- некуда слать трафик => Connection refused

# Причина: selector сервиса не совпадает с labels подов
kubectl -n lab get svc net-demo -o jsonpath='{.spec.selector}{"\n"}'
# {"app":"net-demo-wrong"}     <- а поды помечены app=net-demo
```

**Решение:**

```bash
kubectl -n lab apply -f solutions/01-selector-mismatch/svc.yaml
kubectl -n lab get endpoints net-demo -o wide
# net-demo   10.20.x.x:80   <- selector совпал, backend появился
```

**Профилактика:** selector сервиса и labels подов — единый контракт; держать их
рядом/генерировать из одного источника (kustomize commonLabels, Helm).

### Инцидент 2: после default-deny всё «отвалилось»

```bash
# Симптом (на кластере с enforcement): применили default-deny — приложение
# перестало отвечать И сломался DNS-резолв во всех подах namespace.
# Диагностика — посмотреть, какие политики висят и что они режут:
kubectl -n lab get netpol
kubectl -n lab describe netpol default-deny
# Решение: добавить allow-dns (egress :53) и нужные allow-правила.
# Урок 1: default-deny без allow-dns ломает резолв — DNS разрешают всегда первым.
# Урок 2: при nodelocaldns (Kubespray) egress :53 нужен к 169.254.25.10/32, а не
#         только к поду CoreDNS — иначе резолв останется сломанным (см. note в 4.1).
```

### Бонус: диагностика цепочки Ingress → Service → Endpoints → Pod

```bash
kubectl -n lab get ingress net-demo                 # есть ли адрес (есть ли контроллер)
kubectl -n lab get svc net-demo                     # тот ли порт/тип
kubectl -n lab get endpoints net-demo -o wide       # есть ли backend (selector/readiness)
kubectl -n lab get pods -l app=net-demo             # Ready ли поды
kubectl -n lab logs deploy/net-demo --tail=20       # что говорит приложение
```

**Контрольные вопросы:**
1. Пустой `Endpoints` при Running-подах — каковы две частые причины?
2. Почему default-deny часто «ломает» DNS и как это чинится?
3. В каком порядке проверять цепочку при «Ingress не отвечает»?

---

## Проверка модуля

Разверните рабочие манифесты (Service + Ingress) и дайте подам подняться:

```bash
kubectl -n lab apply -f manifests/services/
kubectl -n lab apply -f manifests/ingress/ingress.yaml
kubectl -n lab rollout status deploy/net-demo --timeout=120s

bash verify/verify.sh
# [OK] ingress/net-demo exists
# [OK] module 04 verified
```

`verify.sh` проверяет: namespace `lab` → `Deployment/net-demo` готов →
`Service/net-demo` с непустыми `Endpoints` → наличие `Ingress/net-demo`
(`[OK]` если есть, иначе `[WARN]`). Промежуточные `require_*` молчат; две
`[OK]`-строки — от `ok`-вызовов (ingress + итог). Если оставлен broken-вариант с
selector mismatch — упадёт на `[FAIL] service/net-demo has no ready endpoints in
ns/lab`.

---

## Финальная карта ресурсов модуля

| Ресурс | Тип | Что демонстрирует |
|--------|-----|-------------------|
| `net-demo` | Deployment×2 + Service(ClusterIP) | selector→Endpoints, балансировка |
| `net-demo-nodeport` | Service(NodePort) | внешний порт 30080 на нодах |
| `net-demo` | Ingress | L7-роутинг по host/path (нужен контроллер) |
| `default-deny`/`allow-dns`/`allow-app-ingress`/`allow-app-egress` | NetworkPolicy | allow-list модель: DNS + доступ к app в ОБА конца (нужен CNI-enforcement) |

---

## Теоретические вопросы (итоговые)

### Блок 1: Service и kube-proxy

1. Опишите путь пакета от `curl <ClusterIP>` до Pod. Роль `kube-proxy`.
2. Сравните `ClusterIP`/`NodePort`/`LoadBalancer`/`ExternalName`.
3. Почему пустой `Endpoints` = «Connection refused», и какие две причины этого?
4. iptables vs IPVS: чем отличаются и где iptables деградирует? Какой режим у нашего кластера?
5. `externalTrafficPolicy: Local` vs `Cluster` — что с source-IP и лишним хопом?

### Блок 2: DNS

6. Как резолвится `net-demo.lab.svc.cluster.local`? Кто отвечает?
7. `ndots:5`: сколько DNS-запросов на `api.example.com` и как убрать лишние?
8. Зачем nodelocaldns и на каком адресе он слушает?

### Блок 3: Внешний доступ

9. Чем Ingress принципиально отличается от LoadBalancer-сервиса?
10. Зачем LoadBalancer-сервису под капотом всё равно нужен NodePort?
11. Чем Gateway API лучше Ingress (роли, L4, без «магии» аннотаций)?

### Блок 4: NetworkPolicy

9. Что разрешено по умолчанию и что меняет default-deny?
10. Почему политику для DNS добавляют первой после default-deny?
11. От чего зависит, заработает ли NetworkPolicy вообще?
12. Поток A→B при default-deny: чьи политики (A, B или обеих) должны его
    пропустить? Почему «открыть ingress у backend» без egress у клиента не работает?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Воспроизведите selector-mismatch (svc selector ≠ labels подов) и почините, наблюдая `Endpoints`.
2. Под `default-deny`: уберите `allow-app-egress` и подтвердите, что клиент виснет; верните — проходит.
3. Через под-`busybox` проверьте резолв сервиса по короткому и полному имени; найдите search-домены в `/etc/resolv.conf`.
4. Создайте `NodePort`-сервис и достучитесь до него; объясните разницу с `ClusterIP`.
5. Добавьте egress-allow к конкретному CIDR и проверьте, что трафик к другим адресам режется.

---

## Шпаргалка

```bash
# === Service / Endpoints ===
kubectl -n lab get svc,endpoints -o wide
kubectl -n lab get endpointslices
kubectl -n lab get svc net-demo -o jsonpath='{.spec.selector}'   # с чем должны совпасть labels подов
kubectl -n lab run probe --image=busybox:1.36 --restart=Never -i --rm -- wget -qO- http://net-demo/

# === DNS ===
kubectl -n lab run dnscheck --image=busybox:1.36 --restart=Never -i --rm -- nslookup net-demo.lab.svc.cluster.local
# из пода: cat /etc/resolv.conf   (search-домены, ndots)

# === Внешний доступ ===
kubectl -n lab get svc net-demo-nodeport            # NodePort 30080
kubectl -n lab get ingress net-demo                 # ADDRESS только при наличии контроллера
# LoadBalancer: type: LoadBalancer -> EXTERNAL-IP (платно, удалять после теста)

# === NetworkPolicy ===
kubectl -n lab get netpol
kubectl -n lab describe netpol default-deny
kubectl -n kube-system get pods | grep -E "calico|cilium|dataplane"   # есть ли enforcement

# === Уборка ===
kubectl -n lab delete netpol --all                  # СНЯТЬ политики (default-deny может всё резать!)
kubectl -n lab delete svc net-demo-lb --ignore-not-found    # удалить облачный LB (платный)
kubectl -n lab delete -k manifests/
```

---

## Уборка

```bash
# NetworkPolicy снимаем первыми — иначе default-deny может мешать связи
kubectl -n lab delete netpol --all
# Если создавали LoadBalancer — обязательно удалить (платный облачный ресурс)
kubectl -n lab delete svc net-demo-lb --ignore-not-found
# Остальное
kubectl -n lab delete -k manifests/
```
