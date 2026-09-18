# Kubernetes Labs — Roadmap до полного погружения

Цель: довести лабу от «уверенных основ» до уровня, на котором инженер
самостоятельно проектирует, защищает, масштабирует и обслуживает
production-grade кластеры.

---

## Где мы сейчас (Уровень 1 — Foundation ✅)

10 модулей (`modules/01..10`) обогащены до глубины эталона и прогнаны на стенде
Kubespray (GKE удалён 2026-06-02):

| # | Модуль | Покрывает |
|---|--------|-----------|
| 01 | kubectl-basics | API-модель, контексты, namespaces, диагностика |
| 02 | pods-lifecycle | фазы, init, пробы, QoS/OOM, graceful shutdown |
| 03 | workloads | Deployment/Job/CronJob/DaemonSet/StatefulSet |
| 04 | networking | Service/DNS/Ingress/NetworkPolicy |
| 05 | storage | volumes/PV/PVC/StorageClass/StatefulSet |
| 06 | scheduling | nodeSelector/taints/affinity/quota |
| 07 | config-security | ConfigMap/Secret/RBAC/securityContext |
| 08 | observability | events/conditions/logs/metrics/runbook |
| 09 | helm-gitops | Helm chart + Argo CD |
| 10 | kubeadm-admin | cordon/drain/PDB/static-pods/certs |

+ 3 проекта: `project-a-platform-namespace`, `project-b-stateful-service`,
`project-c-broken-cluster-lab`.

**Вывод:** покрыты основы. Не покрыто: autoscaling, реальный observability-стек,
расширяемость (CRD/Operators), глубокая безопасность (admission/policy), mesh,
progressive delivery, backup/DR. Это и есть план ниже.

---

## Уровень 2 — Reliability & Scaling

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 11 | [x] | **autoscaling** `c9f0c86` | HPA/VPA/Cluster Autoscaler — прогнан вживую |
| 12 | [x] | **resource-management** `c7e1338` | QoS-классы + PriorityClass/preemption + limits enforcement |
| 13 | [x] | **resilience** `ef90589` | topologySpread + antiAffinity + PDB + cordon/drain |

## Уровень 3 — Security hardening

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 14 | [x] | **pod-security-admission** `5aea74d` | PSA restricted + ValidatingAdmissionPolicy (CEL) |
| 15 | [x] | **network-policy-enforced** `350f848` | микросегментация web→api→db — прогнан на Kubespray+Calico |
| 16 | [x] | **secrets-management** `de6069a` | encryption-at-rest + Sealed Secrets + ESO + Vault DYNAMIC secrets |

## Уровень 4 — Observability stack (реальный)

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 17 | [x] | **metrics-alerting** `46be54c` | Prometheus+Grafana+Alertmanager, ServiceMonitor, PromQL |
| 18 | [x] | **logs-tracing** `29bf5f1` | Loki/EFK, Promtail (трассировка вынесена в модуль 30) |

## Уровень 5 — Extensibility & advanced workloads

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 19 | [x] | **crd-operators** `2b2c4f0` | CRD + схема/валидация + operator pattern (prometheus-operator) |
| 20 | [x] | **batch-workflows** | Job parallelism/completions, Indexed Jobs, CronJob |
| 21 | [x] | **stateful-systems** `29bf5f1` | DB-операторы (CloudNativePG), failover |

## Уровень 6 — Networking advanced

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 22 | [x] | **ingress-tls** `938b97e` | L7 routing + TLS termination (ingress-nginx + cert-manager) |
| 23 | [x] | **gateway-api** | Gateway API (замена Ingress), HTTPRoute, traffic shifting, TLS |

## Уровень 7 — Delivery & GitOps advanced

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 24 | [x] | **progressive-delivery** | Argo Rollouts, canary/blue-green |
| 25 | [x] | **gitops-at-scale** | Kustomize, ApplicationSet, AppProject-границы, prune/selfHeal |

## Уровень 8 — Cluster operations & DR

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 26 | [ ] | **backup-dr** → Волна 2 плана расширения | Velero + MinIO (backup/restore), etcd snapshot/restore |
| 27 | [ ] | **upgrades-lifecycle** → Волна 2 плана расширения | Kubespray upgrade-cluster.yml, surge/PDB, deprecated API |
| 28 | [x] | [28-cost-multitenancy](../modules/28-cost-multitenancy) ✅ ГОТОВ | HNC (иерархия ns, propagation), vcluster 0.34 (hard multi-tenancy, host-квота), FinOps showback/rightsizing на PromQL |

## Уровень 9 — Современные API и Observability v2

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 29 | [x] | **pod-lifecycle-v2** | native sidecars (GA 1.33), scheduling gates, in-place resize — прогнан на Kubespray v1.36.1 |
| 30 | [x] | **tracing-otel** | OTel SDK→Collector→Tempo 3.0, TraceQL, корреляция trace↔log (Loki derivedFields + tracesToLogsV2) — закрывает «без трассировки» из уровня 4; прогнан на Kubespray v1.36.1 |

Дальние кандидаты уровня 9+: service mesh (Linkerd/Istio ambient — последний
непокрытый пункт исходного списка), admission webhooks hands-on, supply-chain
security (trivy/cosign/Kyverno verifyImages), runtime security + audit
(Falco/kube-bench/audit policy), Kueue/KEDA practice.

---

## Capstone-проекты

| Проект | Статус | Название | Содержание |
|--------|:---:|----------|------------|
| Project A | [x] | **platform-namespace** | Базовый namespace (Quota, LimitRange, Role) |
| Project B | [x] | **stateful-service** | StatefulSet, headless svc |
| Project C | [x] | **broken-cluster-lab** | (Алиас для Project F) |
| Project D | [x] | **production-readiness** | Аудит 11 критериев (PDB, probes, limits, replicas) |
| Project E | [x] | **secure-platform** | Multi-tenant изоляция (5 контролей: PSA, VAP, RBAC, Quota, NetPol) |
| Project F | [x] | **incident-response** | 8 инцидентов + авто-триаж `incident-triage.sh` |

---

## План большого расширения (2026-Q4 → 2027-Q2)

Отдельные k8s-лабы вне курса (инциденты, симуляторы CKA/CKAD/CKS, лаба для разработчиков,
оператор-dev, deep-dive по сети/storage, day-2 SRE) — в [`NEW-LABS-PLAN.md`](./NEW-LABS-PLAN.md).

Снимок на 2026-09-19: 28 модулей + 5 capstone, все по эталону формата (README с
mermaid-схемами, `tasks/` с ожидаемым результатом, `broken/` ×2, `verify/` с
prepare/cleanup); учебный стенд — Kubespray на GCE (сейчас выключен, billing).
Ниже — что добавлять дальше, волнами. Основа — `NEW-MODULES-DESIGN.md` из
handoff-пакета (12 NM-модулей с привязкой к GA-версиям) и отчёт missing-topics;
из него уже сделаны NM-1 (m29), NM-5 (m23), NM-13 (m28), NM-14 (m30), KEDA (m11/04).

### Принципы

- **Reality-first.** Модуль существует только если его практика проходит на стенде.
  Нет железа/облака — берём эмулятор (dra-example-driver, provider-kubernetes,
  MinIO вместо S3, локальный registry), а не «представьте, что у вас GPU».
- **Definition of Done модуля:** README по эталону m29/m30 (⏱ честное, теория перед
  частью, mermaid), ≥3 задачи с «Ожидаемый результат», `broken/` ×2 (уровни 1 и 2 из
  `scripts/qa/mutate.py --list`) + `solutions/`, `verify/` поведенческий + prepare
  fail-fast + cleanup без persistent-аддонов, sweep зелёный на стенде, выводы в README
  сняты со стенда, запись в learning path и в этот ROADMAP.
- **RAM-дисциплина стенда** (3×e2-medium): не больше двух тяжёлых аддонов одновременно;
  Falco/Tetragon, Knative, Cilium — на отдельных профилях кластера, не поверх базового.
- **Аддоны — persistent через `scripts/bootstrap/NN-*.sh`** и `up.sh --addons`; модуль
  их не ставит и не сносит.

### Волна 0 — стабилизация (≈2 недели, нужен включённый стенд)

| # | Задача | Зачем |
|---|---|---|
| W0.1 | Полный `sweep.sh` после сентябрьской полировки; починить красное | verify m15–m30, задачи m21/m23 и scenario-02 у 11 модулей ещё не исполнялись на стенде |
| W0.2 | **MinIO** в кластере как persistent-аддон (`scripts/bootstrap/12-install-minio.sh`, ns `minio`) | закрывает бэкап m21 (T7.2c) и становится S3 для Velero (26), registry (32), Loki/Tempo при желании |
| W0.3 | Nightly QA: cron на рабочей машине `start.sh → sweep.sh → отчёт → stop.sh` | регрессии ловятся сами, стенд платит только за час |
| W0.4 | Ответы на итоговые вопросы во всех модулях (`<details>`), scenario-03 уровня 3 через `mutate.py` | самопроверка студента; сейчас ответов нет ни в одном модуле |
| W0.5 | Усиление сети в существующих модулях: m04 — EndpointSlice, `trafficPolicy`, headless/hairpin как практика; m15 — AdminNetworkPolicy и таблица enforcement; m22/m23 — таймауты/keepalive как broken; m10 — kube-proxy как компонент ноды | сеть — самая слабая тема курса и собеседований; текст без стенда, выводы — со стенда |

### Волна 1 — Security & Policy, трек CKS (≈4 недели)

| # | Модуль | Содержание | Аддоны | Reality | Оценка |
|---|---|---|---|---|---|
| 31 | `policy-as-code` (NM-7) | Kyverno validate/mutate/**generate** (default-deny и квота на каждый новый ns) против нашей VAP; MutatingAdmissionPolicy на CEL; hardening: `hostUsers: false` (user namespaces), `recursiveReadOnly` | Kyverno (helm, лёгкий) | 🟢 | 3–4 дня |
| 32 | `supply-chain-security` (NM-8) | `registry:2` в кластере (backend MinIO); cosign key-based sign/verify; syft SBOM + attestation; trivy как gate; Kyverno `verifyImages` блокирует неподписанное | registry, бинарники cosign/syft/trivy | 🟡 | 4–5 дней |
| 33 | `runtime-security` (NM-10) | Falco (modern-bpf): shell в prod-поде, неожиданный egress; Tetragon TracingPolicy; алерт → Alertmanager (m17) | Falco, Tetragon | 🔵 ядро GCE подходит, RAM тесно — отдельный профиль | 4–5 дней |
| G | `project-g-cks-mock` | 12 задач на время по m14/15/16/31/32/33 + случайные инциденты; таймер, критерии как на экзамене | — | 🟢 | 2 дня |
| doc | `docs/05-cert-matrix.md` | покрытие CKA/CKAD/CKS по модулям и задачам, пробелы | — | — | 1 день |

### Волна 2 — Platform & DR (≈5 недель)

| # | Модуль | Содержание | Аддоны | Reality | Оценка |
|---|---|---|---|---|---|
| 26 | `backup-dr` (NM-12) | Velero + MinIO: Backup/Schedule, restore в новый ns после «случайного delete», restore hooks; etcd snapshot/restore-учение на одноразовом стенде; RTO/RPO | Velero (+ W0.2) | 🟡 | 4 дня |
| 27 | `upgrades-lifecycle` | Kubespray `upgrade-cluster.yml` 1.36→1.37 на клоне стенда (`down.sh`/`up.sh`), surge и PDB во время upgrade, version skew, поиск deprecated API (`pluto`/`kubectl-convert`) | — | 🟡 одноразовый стенд | 3 дня |
| 34 | `platform-engineering` (NM-11) | Crossplane + provider-kubernetes/helm: XRD + Composition «WebService» (claim → Deployment+Service+HPA), self-service с ограниченным RBAC; сравнение с Helm/оператором m19 | Crossplane | 🟡 | 4–5 дней |
| 35 | `batch-v2` (NM-4) | Kueue: ClusterQueue/LocalQueue/ResourceFlavor, admission по квоте; JobSet (imitация master+workers); gang scheduling через scheduling gates (m29); priority preemption | Kueue, JobSet | 🟡 | 3–4 дня |
| 36 | `devices-dra` (NM-3) | DRA: DeviceClass/ResourceClaim/ResourceClaimTemplate на `dra-example-driver` (фейковые устройства, без GPU), shared claim, отказ аллокации как broken | dra-example-driver | 🟡 | 3 дня |

### Волна 3 — Networking v2, serverless, mesh, multi-cluster (≈6 недель)

| # | Модуль | Содержание | Аддоны | Reality | Оценка |
|---|---|---|---|---|---|
| 37 | `cilium-hubble` | второй профиль стенда `cluster-kubespray-cilium` (`kube_network_plugin: cilium`): CiliumNetworkPolicy L7 (HTTP-путь), Hubble flows/UI, DNS-политики; сравнение с Calico (m15) | отдельный кластер | 🟡 | 5 дней + IaC |
| 41 | `services-internals` | kube-proxy iptables/ipvs/nftables на стенде, EndpointSlice, trafficPolicy, hairpin, conntrack — «путь пакета» (усиление сети; полный трек — L7 в NEW-LABS-PLAN) | — | 🟢 | 4 дня |
| 42 | `dns-deep-dive` | CoreDNS/nodelocaldns стенда, ndots, stub-домены, кэш, отладка | — | 🟢 | 3 дня |
| 43 | `loadbalancer-bare-metal` | MetalLB/kube-vip: настоящий LoadBalancer на стенде вместо `<pending>` | MetalLB | 🟡 | 3 дня |
| 38 | `serverless-knative` (NM-6) | Knative Serving поверх Gateway API (m23): scale-to-zero, cold start, revisions, traffic split; связь с KEDA (m11/04) | Knative | 🟡 RAM | 4 дня |
| 39 | `service-mesh` | Linkerd (лёгкий): mTLS, retries/timeouts, golden metrics, traffic split; когда mesh, а когда хватает Gateway API | Linkerd | 🟡 | 4–5 дней |
| 40 | `multi-cluster` | второй кластер — локальный k3s (уже есть на рабочей машине): контексты, Argo CD multi-cluster + ApplicationSet cluster generator (m25), федерация секретов (ESO, m16) | — | 🟢 | 4 дня |

### Сквозные задачи (параллельно волнам)

- Экзамен-режим курса: таймер + `chaos/random-incident.sh` (project-c) + случайный
  broken из любого модуля — «незнакомый инцидент за 20 минут».
- Learning path: треки «Security/CKS» (14, 15, 16, 31, 32, 33, G), «Platform» (19, 25,
  26, 27, 34, 35, 36), «Networking v2» (04, 15, 22, 23, 41, 42, 43, 37, 38, 39) — сеть
  усилена: три новых модуля про внутренности Service/DNS/LB идут ДО Cilium и mesh.
- Бейдж nightly-sweep в README; `docs/00-cluster-baseline.md` с полным списком
  persistent-аддонов и их RAM.

### Порядок и оценка

Волна 0 (2 нед) → 1 (4 нед) → 2 (5 нед) → 3 (6 нед): ~4 месяца при половинной
занятости. Каждая волна заканчивается зелёным sweep и обновлением learning path;
модули внутри волны независимы и делаются по одному (DoD выше).

