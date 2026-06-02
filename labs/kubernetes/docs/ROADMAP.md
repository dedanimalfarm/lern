# Kubernetes Labs — Roadmap до полного погружения

Цель: довести лабу от «уверенных основ» до уровня, на котором инженер
самостоятельно проектирует, защищает, масштабирует и обслуживает
production-grade кластеры.

---

## Где мы сейчас (Уровень 1 — Foundation ✅)

10 модулей (`modules/01..10`) обогащены до глубины эталона и прогнаны на реальном
GKE:

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

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 11 | **autoscaling** ✅ ГОТОВ `c9f0c86` | HPA/VPA/Cluster Autoscaler — прогнан вживую (scale-up 1→5 под нагрузкой) | ✅ |
| 12 | **resource-management** | PriorityClass, preemption, requests/limits tuning, bin-packing | любой ✅ |
| 13 | **resilience** | PodDisruptionBudget-паттерны, topologySpreadConstraints, multi-zone, anti-affinity | multi-zone кластер |

## Уровень 3 — Security hardening

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 14 | **pod-security-admission** | Pod Security Standards, Kyverno/OPA Gatekeeper, ValidatingAdmissionPolicy | любой ✅ |
| 15 | **network-policy-enforced** ✅ ГОТОВ `350f848` | микросегментация web→api→db — прогнан на Kubespray+Calico (web→db заблокировано) | Calico ✅ |
| 16 | **secrets-management** | encryption-at-rest, external-secrets, sealed-secrets, Vault | GKE + внешний менеджер |

> ⚠️ Модуль 15 не отработает на текущем GKE (без Dataplane V2). Варианты: пересоздать
> кластер с `datapath_provider=ADVANCED_DATAPATH`, либо kind + Calico.

## Уровень 4 — Observability stack (реальный)

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 17 | **metrics-alerting** | Prometheus + Grafana + Alertmanager, kube-state-metrics, ServiceMonitor, PromQL | GKE (вернуть ноды) ✅ |
| 18 | **logs-tracing** | Loki/EFK, OpenTelemetry, Jaeger, distributed tracing | GKE ✅ |

## Уровень 5 — Extensibility & advanced workloads

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 19 | **crd-operators** | CustomResourceDefinition, controller pattern, kubebuilder/operator-sdk, sample operator | любой ✅ |
| 20 | **batch-workflows** | Argo Workflows, Job parallelism/completions, indexed Jobs | любой ✅ |
| 21 | **stateful-systems** | DB-операторы (CloudNativePG/Redis), backup, StatefulSet advanced | GKE + storage |

## Уровень 6 — Networking advanced

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 22 | **ingress-tls-gateway** | cert-manager, TLS termination, Gateway API | GKE + ingress-controller |
| 23 | **service-mesh** | Istio/Linkerd: mTLS, traffic shifting, retries, mesh-observability | GKE (вернуть ноды) |

## Уровень 7 — Delivery & GitOps advanced

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 24 | **progressive-delivery** | Argo Rollouts, canary/blue-green, Flagger, analysis | GKE + Argo |
| 25 | **gitops-at-scale** | ApplicationSets, sync waves/hooks, Kustomize overlays, multi-env | любой ✅ |

## Уровень 8 — Cluster operations & DR

| # | Новый модуль | Ключевое | Среда |
|---|--------------|----------|-------|
| 26 | **backup-dr** | Velero (backup/restore), etcd snapshot/restore | self-managed для etcd |
| 27 | **upgrades-lifecycle** | cluster/node upgrades, surge, Cluster API | kubeadm/GKE |
| 28 | **cost-multitenancy** | FinOps, spot/preemptible, hierarchical namespaces, vcluster | GKE ✅ |

---

## Capstone-проекты (расширить существующие + добавить)

- **D — production-app**: микросервис + HPA + Ingress/TLS + Prometheus + Argo CD
  (собирает уровни 2-4, 7 в одном сквозном проекте).
- **E — secure-platform**: multi-tenant платформа с Pod Security, NetworkPolicy,
  RBAC, quota, policy-as-code (уровень 3).
- **F — incident-response**: расширить `project-c-broken-cluster-lab` сценариями
  из новых модулей (OOM, eviction, DNS, cert-expiry, sync-fail).

---

## Приоритизация (с чего начинать)

**Phase 1 (наибольшая ценность, работает на текущем GKE):**
- 11 autoscaling (HPA) — частый production-навык, демонстрируется сразу.
- 14 pod-security-admission (Kyverno) — закрывает разрыв 07 до реальных политик.
- 17 metrics-alerting (Prometheus/Grafana) — поднимает 08 до настоящего стека.
- 19 crd-operators — фундамент понимания «как устроен сам K8s».

**Phase 2:** 12, 13, 16, 18, 20, 25 (углубление reliability/observability/delivery).

**Phase 3:** 15 (нужен Calico/Dataplane V2), 21, 22, 23, 24, 26, 27, 28 + capstone D/E/F.

---

## Заметки по среде

- Текущий GKE (`cluster-gke/`) сейчас «припаркован» (0 нод). Для модулей 11/17/23
  вернуть ноды: `terraform apply` (node_count=2).
- Для NetworkPolicy enforcement (15) и части mesh-сценариев — отдельный кластер
  с advanced datapath или локальный kind + Calico.
- Формат новых модулей — тот же скелет, что у 01-10 (теория→команды с «зачем»+
  выводом→контрольные→troubleshooting→проверка→карта→вопросы→шпаргалка→уборка),
  с `verify/verify.sh` и прогоном на реальном кластере.
