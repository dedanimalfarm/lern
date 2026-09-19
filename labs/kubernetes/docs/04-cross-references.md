# Kubernetes Labs: Карта перекрестных ссылок (Cross-References)

Этот документ показывает, как модули зависят друг от друга и какие концепции получают развитие в продвинутых темах. Если вы хотите углубить знания в конкретной области, используйте эту таблицу для навигации.

| Тема / Механизм | Базовый модуль | Продвинутый модуль / Проект | Как развивается |
|-----------------|----------------|-----------------------------|-----------------|
| **Жизненный цикл Pod** | `m02` (Pods) | `m20` (Batch/Jobs) | Управление падениями через podFailurePolicy и индексированные джобы. |
| **Управление ресурсами** | `m02` (QoS/OOM) | `m12` (Resource Mgmt) | От requests/limits к PriorityClass и вытеснению (Preemption). |
| **Безопасность (Pod)** | `m07` (SecurityContext) | `m14` (PodSecurityAdmission) | От ручного ограничения (runAsUser) к принудительным политикам на уровне кластера (PSA/VAP). |
| **Сетевая изоляция** | `m04` (NetworkPolicy) | `m15` (NetPol Enforced) | От базового синтаксиса к микросегментации (default-deny, web→api→db). |
| **Хранение данных** | `m05` (Storage/StatefulSet) | `m21` (Stateful Systems) | От ручного StatefulSet к мощным операторам (CloudNativePG) с failover и backup. |
| **Секреты** | `m07` (Secrets) | `m16` (Secrets Mgmt) | От Base64 к Vault, External Secrets Operator и шифрованию at-rest. |
| **Метрики** | `m08` (Observability) | `m17` (Metrics/Alerting) | От `kubectl top` к полноценному стеку Prometheus, PromQL и Alertmanager. |
| **Маршрутизация (L7)** | `m04` (Ingress) | `m22` (TLS), `m23` (Gateway API) | От простого правила Ingress к TLS-терминации и миграции на современный стандарт Gateway API. |
| **Масштабирование** | `m03` (Deployments) | `m11` (Autoscaling) | От ручного `kubectl scale` к автоматическому HPA/VPA/ClusterAutoscaler. |
| **GitOps и доставка** | `m09` (Helm/GitOps) | `m25` (GitOps at Scale) | От простого Application к ApplicationSet, Kustomize overlays и AppProject. |
| **Стратегии релиза** | `m03` (RollingUpdate) | `m24` (Progressive Delivery) | От RollingUpdate к Canary, Blue/Green и автоматическому анализу в Argo Rollouts. |
| **Отказоустойчивость** | `m06` (Scheduling/Affinity) | `m13` (Resilience) | От базового nodeSelector/Affinity к topologySpreadConstraints и PDB. |
| **Расширяемость API** | `m01` (API-модель) | `m19` (CRD/Operators) | От понимания стандартных ресурсов к созданию собственных CRD и операторов. |
| **Трейсинг** | `m08` (Observability), `m17`/`m18` (Grafana/Loki) | `m30` (Tracing/OTel) | Третий сигнал наблюдаемости: OTLP-конвейер (SDK → Collector → Tempo), TraceQL и корреляция трейсов с логами по trace_id. |
| **Логи** | `m08` (kubectl logs) | `m18` (Centralized Logging) | От логов одного пода к конвейеру Promtail → Loki, LogQL-парсерам и метрикам из логов. |
| **Жизненный цикл Pod v2** | `m02` (init/probes/QoS) | `m29` (Pod Lifecycle v2) | Native sidecars вместо контейнера-логгера, scheduling gates вместо busy-wait, in-place resize вместо пересоздания пода. |
| **SLO и алерты** | `m08` (4.4 SLI/SLO/error budget) | `m17` (Metrics/Alerting) | От определения SLI к recording rules, burn-rate-алертам и маршрутизации в Alertmanager. |
| **Автоскейл по событиям** | `m11` (HPA/VPA) | `m11`, задача `04-keda` | От CPU-метрик к внешним триггерам (cron, очередь, PromQL) и масштабированию в ноль. |
| **Изоляция и стоимость** | `m12` (Quota/LimitRange), `m14` (PSA) | `m28` (Cost/Multi-tenancy) | От namespace с квотой к иерархии (HNC), виртуальным кластерам (vcluster) и showback по requests. |
| **Как CNI исполняет политики** | `m15` (NetworkPolicy) | `m15`, раздел про Calico dataplane | От объекта в API к Felix, цепочкам `cali-tw-/cali-fw-`, ipset и eBPF-режиму на ноде. |
| **Диагностика инцидентов** | `broken/scenario-*` каждого модуля | `project-c` + `chaos/random-incident.sh` | От поломки с известной темой к случайному инциденту без подсказок, на время. |

## Интеграционные проекты (Capstone)

Проекты собирают знания из нескольких модулей воедино:

| Проект | Опирается на модули | Роль проекта |
|--------|---------------------|--------------|
| **Project A (Platform)** | `m04`, `m07`, `m12` | Сборка базового tenant-namespace с лимитами (Quota) и default-deny NetPol. |
| **Project B (Stateful)** | `m05`, `m13`, `m20` | Запуск базы данных со StatefulSet, headless svc, PDB и CronJob бэкапами. |
| **Project D (Production)** | `m03`, `m08`, `m11` | Аудит production-readiness чек-листа (PDB, probes, limits, replicas). |
| **Project E (Secure)** | `m07`, `m12`, `m14`, `m15` | Multi-tenant изоляция с использованием PSA, VAP, NetPol и RBAC (5 контролей). |
| **Project F (Incident)** | *Все базовые* | Troubleshooting боевых инцидентов (CrashLoop, Pending, Network-deny, Cert-expiry) с триаж-скриптом. |

## Инструменты курса

| Инструмент | Что делает | Когда нужен |
|---|---|---|
| `scripts/qa/run-module.sh <путь>` | prepare → apply манифестов → verify → cleanup через trap | проверить один модуль после правок |
| `scripts/qa/sweep.sh [цели]` | прогон всех (или указанных) модулей и проектов, отчёт в markdown; восстанавливает quota/LimitRange между модулями | регрессия перед коммитом и в CI |
| `scripts/qa/lint.sh` | yamllint + kubeconform + shellcheck + kustomize build | до коммита (CI дублирует) |
| `scripts/qa/mutate.py <манифест> <мутация>` | портит эталонный манифест типовой ошибкой (12 мутаций, 3 уровня), `--hint` печатает симптом и первую команду | заготовка нового broken-сценария |
| `scripts/qa/add-toc.sh`, `add-nav.sh` | оглавление и навигация «предыдущий · следующий» в README | после добавления или переименования модуля |
| `scripts/cluster/{up,start,stop,down}.sh` | жизненный цикл стенда Kubespray (`up.sh --addons` — со всеми persistent-аддонами) | начало и конец работы |
| `scripts/cluster/nightly.sh` | start → проверка аддонов → sweep → отчёт → stop | ночная регрессия по cron |
| `scripts/qa/exam.sh` | экзамен по всему курсу: N случайных broken-сценариев из разных модулей, таймер, зачёт по verify (`start N` / `check` / `status` / `reveal` / `reset`) | самопроверка после прохождения курса |
| `projects/project-c/chaos/random-incident.sh` | случайные инциденты без подсказок (`start N` / `reveal` / `reset`) | экзамен-режим |
