# Карта обучения (Learning Path)

Рекомендуемые треки прохождения лаборатории. Время — оценка на полный проход модуля
(теория, практика, задачи из `tasks/`, один broken-сценарий) и совпадает со строкой
«⏱» в README модуля; сложность — от 1 до 5. Всё гоняется на одном стенде — Kubespray
(3 VM, Calico, k8s 1.36).

## Треки обучения

### 1. Основы Kubernetes (Core) — ~7,5 ч
Фундамент работы с кластером. Пререквизиты: базовое знание Linux и Docker.
* **[01-kubectl-basics](../modules/01-kubectl-basics)** (60 мин, сложность 1/5)
* **[02-pods-lifecycle](../modules/02-pods-lifecycle)** (60 мин, сложность 2/5)
* **[03-workloads](../modules/03-workloads)** (60 мин, сложность 2/5)
* **[04-networking](../modules/04-networking)** (60 мин, сложность 3/5)
* **[05-storage](../modules/05-storage)** (75 мин, сложность 2/5)
* **[06-scheduling](../modules/06-scheduling)** (45 мин, сложность 2/5)
* **[07-config-security](../modules/07-config-security)** (45 мин, сложность 2/5)
* **[29-pod-lifecycle-v2](../modules/29-pod-lifecycle-v2)** (45 мин, сложность 3/5) — продолжение 02: native sidecars, scheduling gates, in-place resize (нужен k8s ≥ 1.33)

### 2. Эксплуатация и наблюдаемость (Operations & Observability) — ~8 ч
Как кластер работает внутри и как мониторить сервисы. Пререквизиты: Трек 1.
* **[08-observability](../modules/08-observability)** (35 мин, сложность 2/5)
* **[10-kubeadm-admin](../modules/10-kubeadm-admin)** (60 мин, сложность 4/5)
* **[17-metrics-alerting](../modules/17-metrics-alerting)** (60–90 мин, сложность 4/5)
* **[18-centralized-logging](../modules/18-centralized-logging)** (90 мин, сложность 3/5)
* **[30-tracing-otel](../modules/30-tracing-otel)** (60 мин, сложность 4/5) — пререквизиты: 17, 18
* **[20-batch-workflows](../modules/20-batch-workflows)** (45 мин, сложность 3/5)
* **[Project F: Incident Response](../projects/project-c-broken-cluster-lab)** (90 мин, сложность 5/5) — *Capstone*, включает режим случайного инцидента

### 3. Поставка и отказоустойчивость (Delivery & Resilience) — ~9 ч
Для инженеров CI/CD и платформы: выкатывать надёжно и без даунтайма. Пререквизиты: Трек 1.
* **[09-helm-gitops](../modules/09-helm-gitops)** (45 мин, сложность 3/5)
* **[11-autoscaling](../modules/11-autoscaling)** (45 мин, сложность 4/5)
* **[12-resource-management](../modules/12-resource-management)** (35 мин, сложность 3/5)
* **[13-resilience](../modules/13-resilience)** (35–45 мин, сложность 3/5)
* **[21-stateful-systems](../modules/21-stateful-systems)** (45 мин, сложность 4/5)
* **[22-ingress-tls](../modules/22-ingress-tls)** (45 мин, сложность 4/5)
* **[23-gateway-api](../modules/23-gateway-api)** (45 мин, сложность 4/5) — преемник Ingress; пререквизит: 22
* **[24-progressive-delivery](../modules/24-progressive-delivery)** (60–90 мин, сложность 4/5) — canary/blue-green с Argo Rollouts; пререквизиты: 09, 17
* **[25-gitops-at-scale](../modules/25-gitops-at-scale)** (60–90 мин, сложность 4/5)

### 4. Безопасность, расширения и multi-tenancy (Security & Extensions) — ~6 ч
Для DevSecOps и разработки операторов. Пререквизиты: Трек 1 и Трек 3.
* **[14-pod-security-admission](../modules/14-pod-security-admission)** (60 мин, сложность 4/5)
* **[15-network-policy-enforced](../modules/15-network-policy-enforced)** (45 мин, сложность 4/5)
* **[16-secrets-management](../modules/16-secrets-management)** (35–45 мин, сложность 3/5)
* **[19-crd-operators](../modules/19-crd-operators)** (45–60 мин, сложность 4.5/5)
* **[28-cost-multitenancy](../modules/28-cost-multitenancy)** (90–120 мин, сложность 5/5) — HNC, vcluster, FinOps; пререквизиты: 12, 14, 17

## Итоговые проекты (Capstone)
Закрепляют треки. Каждый — самостоятельная сборка с критериями приёмки и аудит-скриптом.
* **[Project A: Platform Namespace](../projects/project-a-platform-namespace)** (30 мин, сложность 2/5) — tenant-namespace: PSA, квоты, LimitRange, default-deny, RBAC. После Трека 1.
* **[Project B: Stateful Service](../projects/project-b-stateful-service)** (35 мин, сложность 3/5) — Redis StatefulSet с PVC на реплику, PDB и бэкапом на отдельный том. После Трека 1.
* **[Project D: Production Readiness](../projects/project-d-production-readiness)** (60 мин, сложность 4/5) — аудит прод-готовности приложения по 11 критериям. После Трека 3.
* **[Project E: Secure Multi-Tenant Platform](../projects/project-e-secure-platform)** (90 мин, сложность 5/5) — защищённая мульти-тенант платформа с изоляцией политиками. После Трека 4.
* **[Project F: Incident Response](../projects/project-c-broken-cluster-lab)** (90 мин, сложность 5/5) — триаж и починка инцидентов, включая случайные. После Трека 2.

## Как проходить модуль

1. Прочитать «Теория для изучения перед частью» и пройти практику по README.
2. Сделать задачи из `tasks/` — у каждой есть «Ожидаемый результат», это и есть самопроверка.
3. Сломать и починить `broken/scenario-*` не подглядывая в `solutions/`.
4. Прогнать `scripts/qa/run-module.sh modules/<имя>` — verify должен быть зелёным.
