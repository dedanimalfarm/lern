# План других лаб по Kubernetes

Курс `labs/kubernetes` — линейная программа «от kubectl до платформы» (28 модулей + 5
capstone; расширение — в [`ROADMAP.md`](./ROADMAP.md)). Ниже — **отдельные лабы**, которые
решают другие задачи: экзамен на время, разбор инцидентов, другая аудитория (разработчики),
глубокое погружение в одну подсистему. Каждая — свой каталог `labs/kubernetes-<имя>/` со
своим README, но на общей QA-обвязке курса (`../kubernetes/scripts/{qa,verify}`, `mutate.py`,
`add-toc`) и на тех же стендах.

Стенды: **Kubespray** (3 ноды, control-plane по SSH, все аддоны) — для control-plane,
сети, storage, экзаменов; **локальный k3s** (single-node на рабочей машине) — для
всего app-уровня и быстрых проверок в CI (kind).

## Сводка

| # | Лаба | Для кого | Суть | Стенд | Объём | Приоритет |
|---|---|---|---|---|---|---|
| L1 | `kubernetes-incidents` | ops/SRE после треков 1–2 | 30 самостоятельных инцидентов «симптом → триаж → fix» по всем слоям, экзамен-режим, счёт | k3s + Kubespray | 30 инцидентов | **P1** |
| L2 | `kubernetes-cka-sim` | кандидаты CKA | симулятор экзамена: задания по доменам CKA с весами, таймер, автогрейдер | Kubespray | 3 варианта × 17 задач | **P1** |
| L3 | `kubernetes-interview` | все уровни | вопросы junior/middle/senior с практическими мини-задачами и ответами | k3s | ~150 вопросов | P2 (дёшево) |
| L4 | `kubernetes-for-developers` | разработчики | от приложения к кластеру: контейнеризация, probes, конфиг, отладка, helm, локальная разработка | k3s | 10 модулей | P2 |
| L5 | `kubernetes-operator-dev` | те, кто прошёл m19 | написать оператор целиком: CRD-дизайн, reconcile, status, finalizers, webhooks, тесты, упаковка | kind/k3s | 8 модулей | P2 |
| L6 | `kubernetes-ckad-sim` / `kubernetes-cks-sim` | кандидаты CKAD/CKS | симуляторы по тому же движку, что L2 | k3s / Kubespray | 2 × 3 варианта | P3 (после L2 и волны 1) |
| L7 | `kubernetes-networking-deep-dive` | ops/сетевики, все после m04/m15 | **усиленный трек**: модель сети и CNI изнутри, kube-proxy iptables/ipvs/nftables, Services/EndpointSlice, DNS, overlay/MTU, NetworkPolicy v2, LoadBalancer на bare-metal, Gateway API под нагрузкой, Cilium/Hubble, dual-stack, трассировка и 10 сетевых инцидентов | Kubespray + профиль cilium | 12 модулей + инциденты | **P1** |
| L8 | `kubernetes-storage-deep-dive` | ops | CSI-внутренности, Longhorn на 3 нодах, снапшоты, расширение, потеря ноды с данными, бэкап | Kubespray | 7 модулей | P3 |
| L9 | `kubernetes-day2-sre` | SRE | SLO и алерты, runbooks, capacity, chaos (Chaos Mesh), game day, post-mortem | Kubespray | 8 модулей | P3 |

## L1 · `kubernetes-incidents` — лаба инцидентов

**Зачем отдельно.** В курсе broken-сценарии привязаны к теме модуля — студент знает, где
искать. Здесь тема неизвестна: инцидент выдаётся случайно, как в проде. Это самый
востребованный навык (и 25 % CKA).

- **Формат инцидента:** `incidents/NN-<slug>/` = `setup.sh` (ломает, пишет скрытый ответ),
  `README.md` только с симптомом и SLA, `triage.md` (открывается после), `verify.sh`
  (починено ли), `solution/`. Генерация половины — `mutate.py` по эталонным манифестам
  курса, половина — руками (control-plane, DNS, certs, RBAC, GitOps).
- **Каталог (30):** 10 app-уровня (probes, image, quota, OOM, selector, env, secret,
  PDB, HPA, job) · 8 сети (DNS, netpol, Service port, Ingress class, Gateway backend,
  MTU/hairpin, EndpointSlice, kube-proxy) · 5 storage (PVC Pending, RWO multi-attach,
  local-path нода, full disk, wrong SC) · 4 control-plane (cordon, taint, cert expiry,
  kubelet down — только Kubespray) · 3 GitOps/policy (Argo OutOfSync, VAP deny,
  Kyverno generate без RBAC).
- **Режимы:** `run.sh next` (следующий по списку), `run.sh random 3` (экзамен: три
  случайных, таймер 45 мин, счёт по `verify.sh`), `run.sh reveal`.
- **Reuse:** `project-c/chaos/random-incident.sh` и `triage/incident-triage.sh` переезжают
  сюда как ядро; project-c остаётся capstone курса и ссылается на лабу.
- **Оценка:** 3 недели (по 1–2 инцидента в день с прогоном). DoD — каждый инцидент
  воспроизводится на k3s или стенде, `verify.sh` зелёный после `solution/`.

## L2 · `kubernetes-cka-sim` — симулятор CKA

- **Домены CKA (актуальная программа):** Troubleshooting 30 %, Cluster Architecture,
  Installation & Configuration 25 %, Services & Networking 20 %, Workloads & Scheduling
  15 %, Storage 10 %. Задания привязаны к доменам с весами; ответ — состояние кластера,
  проверяемое `grade.sh`.
- **Формат:** `variants/v1..v3/` по 17 задач; `exam.sh start v1` разворачивает исходное
  состояние (несколько namespace, «сломанный» узел, заготовки), пишет таймер (120 мин),
  `exam.sh grade` считает проценты и показывает разбор. Kubespray обязателен: задачи с
  `kubeadm certs`, etcd snapshot, drain/upgrade узла, static pods, kubeconfig.
- **Reuse:** задания собираются из tasks курса (m01–m13, m10, m22), но без подсказок и с
  чужими именами объектов; экзаменационный «стиль» — imperative kubectl, время.
- **Оценка:** 2 недели на движок + первый вариант, по неделе на v2/v3.

## L3 · `kubernetes-interview` — вопросы и мини-задачи

- Три уровня (junior/middle/senior), ~50 вопросов на уровень, каждый: вопрос → что
  ждёт интервьюер → короткая практическая проверка на k3s (1–3 команды) → ответ в
  `<details>`. Формат уже есть в `linux-basics/networking/INTERVIEW_QA.md`.
- Источник — «Теоретические вопросы» 28 модулей (у них ещё нет ответов — делается в
  волне 0) + системные вопросы (архитектура, скедулер, etcd, сеть, безопасность).
- **Оценка:** 1,5 недели. Самая дешёвая лаба с высоким спросом.

## L4 · `kubernetes-for-developers`

Другая аудитория: разработчику не нужен kubeadm и etcd, нужен путь «мой сервис работает в
кластере и я умею его отлаживать».

- **Модули (10):** 01 контейнеризация сервиса (Python/Go, multi-stage, non-root) ·
  02 первый деплой и Service · 03 конфиг и секреты в приложении (env, файлы, reload) ·
  04 health: probes, graceful shutdown, SIGTERM в коде · 05 ресурсы и что такое OOM для
  приложения · 06 логи и метрики из кода (structured logs, /metrics) · 07 отладка: exec,
  ephemeral containers, port-forward, `kubectl debug` · 08 Helm-чарт своего сервиса ·
  09 локальная разработка: Skaffold/Tilt, kind, hot-reload · 10 CI → образ → деплой (GitHub
  Actions) — мост в m09/m24.
- Общий учебный сервис (один репозиторий с приложением), стенд — k3s; broken-сценарии
  про ошибки в *коде* (не ловит SIGTERM, нет readiness, логи в файл).
- **Оценка:** 3 недели.

## L5 · `kubernetes-operator-dev`

Продолжение m19: не «что такое оператор», а «написать и довести до продакшена».

- **Модули (8):** 01 дизайн API (CRD, versions, defaults, CEL-валидация) · 02 reconcile
  на controller-runtime (Go) или kopf (Python) — выбор языка в setup · 03 status и
  conditions, observedGeneration · 04 ownerReferences, finalizers, garbage collection ·
  05 admission webhooks (defaulting/validating) с cert-manager · 06 тесты (envtest / kopf
  testing) и e2e на kind · 07 метрики, лидер-элект, RBAC минимум · 08 упаковка (Helm/OLM)
  и upgrade CRD (conversion).
- Стенд kind/k3s; CI — e2e на kind. Оператор из m19 (`WebApp`) — стартовая точка.
- **Оценка:** 4 недели.

## L6 · симуляторы CKAD и CKS

На движке L2 (`exam.sh`/`grade.sh`): CKAD — app-задачи на k3s (probes, jobs,
multi-container, helm/kustomize, netpol, SecurityContext); CKS — после волны 1 курса
(Kyverno, supply chain, runtime), на Kubespray (audit policy, kube-bench, RBAC hardening,
seccomp/AppArmor). **Оценка:** по 1,5 недели каждый после готовности движка.

## L7 · `kubernetes-networking-deep-dive` — усиленный сетевой трек

**Зачем отдельно и почему P1.** Сеть — самый частый источник «ничего не работает, поды
Running» и самая слабая тема на собеседованиях. В курсе она размазана по m04 (Service/DNS/
Ingress), m15 (NetworkPolicy), m22/m23 (Ingress/Gateway); нет ни одного места, где
студент видит **путь пакета** целиком: от `curl` в поде до veth, iptables/ipvs, overlay,
CNI-политики и обратно. Трек закрывает это и даёт повторяемые сетевые инциденты.

**Модули (12), стенд Kubespray (Calico) + второй профиль `cluster-kubespray-cilium`:**

| # | Модуль | Что делаем руками | Reality |
|---|---|---|---|
| 01 | `network-model` | 4 правила модели k8s, Pod-сеть 10.233.64.0/18 стенда, veth/bridge, `ip netns`/`nsenter` в под, `tcpdump` внутри netns | 🟢 |
| 02 | `cni-internals` | что делает CNI-плагин при создании пода (`/etc/cni/net.d`, `/opt/cni/bin`), Calico IPAM и блоки IP, BGP vs VXLAN на стенде, MTU и почему пакеты режутся | 🟢 |
| 03 | `kube-proxy-modes` | iptables → ipvs → nftables: переключаем на стенде, читаем цепочки `KUBE-SERVICES`/`KUBE-SEP-*`, ipvsadm, что меняется в latency и масштабе; conntrack и «залипшие» соединения | 🟢 (Kubespray умеет все три) |
| 04 | `services-endpointslices` | ClusterIP/NodePort/LoadBalancer/ExternalName/headless изнутри, EndpointSlice и readiness, `internalTrafficPolicy`/`externalTrafficPolicy`, topology hints, hairpin, sessionAffinity | 🟢 |
| 05 | `dns-deep-dive` | CoreDNS Corefile и плагины, nodelocaldns на 169.254.25.10 (наш стенд!), `ndots:5` и лишние запросы, ExternalName/stub-домены, autopath, кэш и TTL, отладка `dnstools` | 🟢 |
| 06 | `loadbalancer-bare-metal` | MetalLB L2 (ARP) на стенде — настоящий `LoadBalancer` вместо `<pending>`, BGP-режим в теории; связка с ingress-nginx/Envoy Gateway | 🟡 (L2 в GCE-подсети — проверить; иначе kube-vip) |
| 07 | `network-policy-v2` | углубление m15: `AdminNetworkPolicy`/`BaselineAdminNetworkPolicy` (кластерный уровень), egress к внешним CIDR, FQDN-политики (Calico), политики на namespace-уровне для тенантов, аудит «что режется» | 🟢/🟡 (ANP — Calico поддержка) |
| 08 | `ingress-gateway-under-load` | ingress-nginx и Envoy Gateway под `hey`/`k6`: keepalive, таймауты, буферы, rate-limit, canary по заголовку, TLS-термнация и HTTP/2; где теряются RPS | 🟢 |
| 09 | `cilium-hubble` | профиль стенда с Cilium: eBPF вместо iptables, CiliumNetworkPolicy L7 (HTTP-метод/путь), Hubble flows/UI, DNS-aware политики; сравнение с Calico по тем же сценариям m15 | 🟡 (второй кластер) |
| 10 | `dual-stack-ipv6` | Kubespray dual-stack: Pod/Service IPv6-CIDR (в inventory уже есть `fd85:…`), `ipFamilyPolicy`, DNS AAAA, политики для двух семейств | 🟡 |
| 11 | `packet-tracing` | методика «пакет пропал»: tcpdump на veth/ноде/overlay, `conntrack -L`, `pwru` (eBPF-трассировка), `iptables-save` diff, Hubble; чек-лист по слоям | 🟢 |
| 12 | `network-incidents` | 10 инцидентов уровня сети для L1 (DNS ndots-шторм, MTU-дроп больших ответов, conntrack table full, hairpin, NodePort без endpoints, netpol без DNS, ExternalName в петле, кривой Ingress class, EndpointSlice без Ready, kube-proxy упал на одной ноде) | 🟢 |

**Усиление существующих модулей курса (делается раньше трека, без стенда — только текст,
с стендом — выводы):** m04 — добавить EndpointSlice вместо Endpoints, `trafficPolicy`,
headless и hairpin как практику; m15 — AdminNetworkPolicy в теории и таблицу «кто что
enforce'ит»; m22/m23 — таймауты/keepalive/лимиты как броук-сценарии; m10 — kube-proxy как
компонент ноды (сейчас только kubelet).

**Reuse и зависимости:** m04, m15, m22, m23 как пререквизиты; профиль cilium — общий с
волной 3 курса (m37 → сюда, в курсе остаётся ссылка); инциденты — в L1.
**Оценка:** 6 недель (12 модулей + профиль cilium в IaC); первые 5 модулей не требуют
ничего, кроме стенда Kubespray.

## L8 · `kubernetes-storage-deep-dive`

CSI: как работает драйвер (расширение m05) · Longhorn на 3 нодах (реплики, потеря ноды
с данными, восстановление) · VolumeSnapshot/restore на CSI с поддержкой снапшотов ·
расширение тома онлайн · StatefulSet и данные при масштабировании/удалении · бэкап
данных (Velero + MinIO из волны 2) · производительность (fio в поде, RWX через NFS).
Стенд Kubespray (Longhorn требует open-iscsi на нодах — доп. шаг в up.sh).
**Оценка:** 3 недели.

## L9 · `kubernetes-day2-sre`

SLO/SLI/error budget на реальных метриках (расширение m08/m17) · дизайн алертов и
маршрутизация (Alertmanager, дежурство) · runbook как код · capacity planning и
rightsizing (VPA, m28 FinOps) · chaos engineering: Chaos Mesh (pod-kill, network delay,
IO stress), эксперименты по гипотезам · game day по сценариям L1 · post-mortem и
blameless-разбор. Стенд Kubespray. **Оценка:** 3 недели.

## Общие правила для всех лаб

- Формат и DoD — как у курса (см. `CLAUDE.md` и ROADMAP «Принципы»): README по эталону,
  mermaid, задачи с ожидаемым результатом, broken/solutions, поведенческий verify, lint
  и sweep в CI, выводы со стенда.
- Обвязка не копируется, а подключается: `ROOT=../kubernetes` для `scripts/verify/helpers.sh`,
  `scripts/qa/{lint.sh,mutate.py,add-toc.sh}`; при первой второй лабе — вынести общее в
  `labs/kubernetes-common/`.
- Одна лаба — один learning path и одна строка в `labs/README.md`.

## Порядок

1. **L3 interview** (1,5 нед) — дёшево, сразу полезно, заодно даёт ответы для волны 0.
2. **L1 incidents** (3 нед) — ядро уже есть (chaos, triage, mutate.py).
3. **L7 networking-deep-dive** (6 нед, модули 01–05 сразу на стенде) — усиление сети как самой слабой темы.
4. **L2 cka-sim** (4 нед) — нужен стенд; движок затем переиспользуется в L6.
5. **L4 for-developers** и **L5 operator-dev** (по 3–4 нед) — параллельно, оба на k3s.
6. L8/L9 — после волн 2–3 курса (нужны MinIO/Velero, Chaos Mesh); модули L7/09–10 — после профиля cilium.

Итого ~5 месяцев последовательно; L1–L5 не зависят от волн курса и могут идти
параллельно с ними.
