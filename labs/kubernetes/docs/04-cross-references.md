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
| **Маршрутизация (L7)** | `m04` (Ingress) | `m22` (Ingress/TLS) | От простого правила Ingress к TLS-терминации с cert-manager. |
| **Масштабирование** | `m03` (Deployments) | `m11` (Autoscaling) | От ручного `kubectl scale` к автоматическому HPA/VPA/ClusterAutoscaler. |
| **GitOps и доставка** | `m09` (Helm/GitOps) | `m25` (GitOps at Scale) | От простого Application к ApplicationSet, Kustomize overlays и AppProject. |
| **Стратегии релиза** | `m03` (RollingUpdate) | `m24` (Progressive Delivery) | От RollingUpdate к Canary, Blue/Green и автоматическому анализу в Argo Rollouts. |
| **Отказоустойчивость** | `m06` (Scheduling/Affinity) | `m13` (Resilience) | От базового nodeSelector/Affinity к topologySpreadConstraints и PDB. |
| **Расширяемость API** | `m01` (API-модель) | `m19` (CRD/Operators) | От понимания стандартных ресурсов к созданию собственных CRD и операторов. |

## Интеграционные проекты (Capstone)

Проекты собирают знания из нескольких модулей воедино:

| Проект | Опирается на модули | Роль проекта |
|--------|---------------------|--------------|
| **Project A (Platform)** | `m04`, `m07`, `m12` | Сборка базового tenant-namespace с лимитами (Quota) и default-deny NetPol. |
| **Project B (Stateful)** | `m05`, `m13`, `m20` | Запуск базы данных со StatefulSet, headless svc, PDB и CronJob бэкапами. |
| **Project D (Production)** | `m03`, `m08`, `m11` | Аудит production-readiness чек-листа (PDB, probes, limits, replicas). |
| **Project E (Secure)** | `m07`, `m12`, `m14`, `m15` | Multi-tenant изоляция с использованием PSA, VAP, NetPol и RBAC (5 контролей). |
| **Project F (Incident)** | *Все базовые* | Troubleshooting боевых инцидентов (CrashLoop, Pending, Network-deny, Cert-expiry) с триаж-скриптом. |
