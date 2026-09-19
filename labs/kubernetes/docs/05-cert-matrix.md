# Покрытие сертификаций CKA / CKAD / CKS

Что из программ CNCF курс закрывает практикой, а что — нет. Таблицы помогают
готовиться: видно, какие модули и задачи отрабатывают домен и где остаются дыры.

> ⚠️ **Проценты доменов приведены по редакции программ 2025 года.** Перед
> экзаменом сверьтесь с первоисточником — CNCF меняет веса и состав:
> [CKA](https://www.cncf.io/training/certification/cka/),
> [CKAD](https://www.cncf.io/training/certification/ckad/),
> [CKS](https://www.cncf.io/training/certification/cks/) (раздел Curriculum).
> Этот файл — карта курса, а не источник правды о программе.

Обозначения покрытия: **полное** — тема отработана практикой с verify;
**частичное** — есть теория и команды, но без полноценной практики или на
эмуляторе; **нет** — в курсе отсутствует (кандидат на добавление, см.
[ROADMAP](./ROADMAP.md)).

## CKA — Certified Kubernetes Administrator

| Домен | Вес | Покрытие | Где в курсе | Чего не хватает |
|---|---|---|---|---|
| Troubleshooting | 30 % | полное | `broken/scenario-01..02` всех 28 модулей, `m02` (дерево по STATUS), `m08` (runbook, logs/events), `project-c` + `chaos/random-incident.sh`, `triage/incident-triage.sh` | — |
| Cluster Architecture, Installation & Configuration | 25 % | частичное | `m10` (cordon/drain, static pods, сертификаты, etcd snapshot, upgrade, join/remove нод + блоки «на стенде Kubespray»), `m07` (RBAC), `m19` (расширение API), `cluster-kubespray/` (реальная установка Ansible) | установка кластера **руками через kubeadm** с нуля (в курсе — Kubespray); HA control-plane; Cluster API |
| Services & Networking | 20 % | частичное | `m04` (Service/DNS/Ingress/NetworkPolicy), `m15` (микросегментация + как Calico исполняет политики), `m22` (Ingress+TLS), `m23` (Gateway API) | kube-proxy iptables/ipvs изнутри, CoreDNS Corefile, EndpointSlice и `trafficPolicy` — запланировано (W0.5, m41–m43) |
| Workloads & Scheduling | 15 % | полное | `m03` (Deployment/DaemonSet/Job/CronJob/StatefulSet, rollout/undo), `m06` (nodeSelector, taints, affinity), `m12` (QoS, PriorityClass, preemption), `m13` (topologySpread, PDB), `m29` (sidecars, gates, resize), `m09` (Helm), `m25` (Kustomize) | — |
| Storage | 10 % | полное | `m05` (volumes, PV/PVC, StorageClass, WaitForFirstConsumer, RWO multi-attach), `m21` (StatefulSet с оператором), `project-b` | расширение тома и снапшоты (CSI без поддержки на стенде) |

**Вывод по CKA:** курс закрывает ~85 % программы. Главные дыры — установка
кластера чистым `kubeadm` и внутренности сети; экзаменационный формат (время,
imperative-команды) — в плане отдельной лабой-симулятором (`NEW-LABS-PLAN.md`, L2).

## CKAD — Certified Kubernetes Application Developer

| Домен | Вес | Покрытие | Где в курсе | Чего не хватает |
|---|---|---|---|---|
| Application Design and Build | 20 % | частичное | `m02` (init/sidecar/probes), `m03` (Job/CronJob), `m20` (parallelism, Indexed, podFailurePolicy), `m29` (native sidecars) | сборка образов (это лаба `labs/docker`), multi-container паттерны глазами разработчика |
| Application Deployment | 20 % | полное | `m03` (стратегии, rollout/undo), `m09` (Helm, Argo CD), `m24` (canary/blue-green), `m25` (Kustomize overlays) | — |
| Application Observability and Maintenance | 15 % | полное | `m08` (events/conditions/logs/top, runbook, SLO), `m17` (метрики приложения, PromQL), `m18` (логи, LogQL), `m30` (трейсинг) | `kubectl debug` / ephemeral containers как практика |
| Application Environment, Configuration and Security | 25 % | полное | `m07` (ConfigMap/Secret/RBAC/securityContext), `m12` (requests/limits, квоты), `m14` (PSA, VAP), `m16` (Sealed Secrets, ESO, Vault), `m19` (CRD как API расширения) | — |
| Services and Networking | 20 % | полное | `m04` (Service/DNS/Ingress/NetworkPolicy), `m22`, `m23` | — |

**Вывод по CKAD:** ~90 %. Не хватает взгляда «со стороны кода» — это отдельная
лаба `kubernetes-for-developers` (L4 в плане).

## CKS — Certified Kubernetes Security Specialist

| Домен | Вес | Покрытие | Где в курсе | Чего не хватает |
|---|---|---|---|---|
| Cluster Setup | 10 % | частичное | `m15` (NetworkPolicy по умолчанию deny), `m22` (TLS), `project-a`/`project-e` (базовый tenant с PSA+квотой+netpol) | CIS-бенчмарк (`kube-bench`), защита ingress-контроллера, проверка бинарников |
| Cluster Hardening | 15 % | частичное | `m07` (RBAC, ServiceAccount, projected-токены), `m10` (сертификаты, kubeconfig), `m14` (PSA, VAP) | минимизация RBAC как отдельное упражнение, отключение автомонтирования токена, обновление кластера как защитная мера |
| System Hardening | 15 % | нет | — (частично в `labs/linux-process-isolation`: seccomp, AppArmor, capabilities, namespaces) | seccomp/AppArmor-профили **в подах**, user namespaces (`hostUsers: false`), минимизация хоста |
| Minimize Microservice Vulnerabilities | 20 % | частичное | `m14` (PSA restricted, VAP на CEL), `m15` (микросегментация), `m16` (секреты, динамические креды Vault) | политики Kyverno (mutate/generate), mTLS/mesh, sandbox-рантаймы (gVisor/Kata) |
| Supply Chain Security | 20 % | нет | `m14` (запрет `:latest` через VAP) — и всё | подпись образов (cosign), SBOM (syft), сканирование (trivy) как admission-гейт, доверенные реестры, анализ Dockerfile |
| Monitoring, Logging and Runtime Security | 20 % | частичное | `m17` (алерты), `m18` (централизованные логи), `m08` (диагностика) | audit policy API-сервера, поведенческий анализ рантайма (Falco/Tetragon), обнаружение аномалий |

**Вывод по CKS:** ~40 %. Это самая большая дыра курса, и она закрывается
Волной 1 плана расширения: `m31 policy-as-code` (Kyverno/MAP, user namespaces),
`m32 supply-chain-security` (cosign/syft/trivy + verifyImages), `m33
runtime-security` (Falco/Tetragon, audit policy) и `project-g-cks-mock`.

## Как готовиться по курсу

| Экзамен | Маршрут по курсу | Оценка времени |
|---|---|---|
| CKA | Трек 1 целиком → `m10`, `m12`, `m13` → `m04`, `m15`, `m22` → `m05`, `m21` → `project-c` (инциденты на время) | ~35–40 ч |
| CKAD | Трек 1 → `m03`, `m09`, `m20`, `m24`, `m25` → `m07`, `m16` → `m08`, `m17`, `m18` | ~30 ч |
| CKS | `m07`, `m14`, `m15`, `m16` → `project-e` → **дождаться Волны 1** (m31–m33) или закрывать самостоятельно по ссылкам из ROADMAP | ~20 ч сейчас, ~35 ч после Волны 1 |

Общее правило для всех трёх: на экзамене нет подсказок и мало времени —
тренируйтесь на `broken/scenario-*` без чтения `solutions/` и на
`projects/project-c-broken-cluster-lab/chaos/random-incident.sh` с таймером.
