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
| 18 | [x] | **logs-tracing** `29bf5f1` | Loki/EFK, Promtail (без трассировки, требует OTel) |

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
| 23 | [ ] | <span style="color:red">**gateway-api / mesh**</span> | Gateway API (замена Ingress), Istio/Linkerd, mTLS, traffic shifting |

## Уровень 7 — Delivery & GitOps advanced

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 24 | [x] | **progressive-delivery** | Argo Rollouts, canary/blue-green |
| 25 | [x] | **gitops-at-scale** | Kustomize, ApplicationSet, AppProject-границы, prune/selfHeal |

## Уровень 8 — Cluster operations & DR

| # | Статус | Новый модуль | Ключевое |
|---|:---:|--------------|----------|
| 26 | [ ] | <span style="color:red">**backup-dr**</span> | Velero (backup/restore), etcd snapshot/restore |
| 27 | [ ] | <span style="color:red">**upgrades-lifecycle**</span> | cluster/node upgrades, surge, Cluster API |
| 28 | [ ] | <span style="color:red">**cost-multitenancy**</span> | FinOps, spot/preemptible, hierarchical namespaces, vcluster |

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
