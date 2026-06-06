# Kubernetes Labs (k8s-labs)

Практический репозиторий для поэтапного освоения Kubernetes. Содержит 21 учебный модуль и 5 итоговых проектов (capstone) для закрепления материала на живом кластере.

## 🚀 Быстрый старт

Убедитесь, что кластер запущен и `kubectl` настроен:
```bash
kubectl cluster-info
kubectl get nodes -o wide
```

Подготовьте учебный стенд (namespace `lab` и базовые квоты):
```bash
./scripts/bootstrap/00-create-namespaces.sh
./scripts/bootstrap/01-apply-quotas.sh
```

## 🗺️ Карта обучения (Learning Path)

Для оптимального погружения ознакомьтесь с [docs/02-learning-path.md](docs/02-learning-path.md), где модули разбиты на тематические треки («Основы», «Delivery», «Безопасность», «Эксплуатация») с оценкой времени и сложности. Ниже представлен полный индекс всех модулей и проектов лаборатории.

## 📦 Модули

1. [01-kubectl-basics](modules/01-kubectl-basics) — Основы kubectl и навигация по кластеру
2. [02-pods-lifecycle](modules/02-pods-lifecycle) — Жизненный цикл Pod (initContainers, probes, QoS/OOM)
3. [03-workloads](modules/03-workloads) — Workload-контроллеры (Deployment, Job/CronJob, DaemonSet, StatefulSet)
4. [04-networking](modules/04-networking) — Сеть в Kubernetes (Service, DNS, Ingress, NetworkPolicy)
5. [05-storage](modules/05-storage) — Хранилище в Kubernetes (volumes, PV/PVC, StatefulSet)
6. [06-scheduling](modules/06-scheduling) — Планирование подов (nodeSelector, taints, affinity, quotas)
7. [07-config-security](modules/07-config-security) — Конфигурация и безопасность (ConfigMap, Secret, RBAC, securityContext)
8. [08-observability](modules/08-observability) — Наблюдаемость (events, conditions, logs, metrics)
9. [09-helm-gitops](modules/09-helm-gitops) — Helm и GitOps (Argo CD)
10. [10-kubeadm-admin](modules/10-kubeadm-admin) — Администрирование kubeadm-кластера
11. [11-autoscaling](modules/11-autoscaling) — Автомасштабирование (HPA, VPA, Cluster Autoscaler)
12. [12-resource-management](modules/12-resource-management) — Управление ресурсами (QoS, PriorityClass, preemption, limits)
13. [13-resilience](modules/13-resilience) — Отказоустойчивость (topologySpread, anti-affinity, PDB)
14. [14-pod-security-admission](modules/14-pod-security-admission) — Pod Security и Admission Control (PSA + ValidatingAdmissionPolicy)
15. [15-network-policy-enforced](modules/15-network-policy-enforced) — NetworkPolicy с реальным enforcement (микросегментация)
16. [16-secrets-management](modules/16-secrets-management) — Управление секретами (encryption-at-rest, Sealed Secrets, ESO, Vault dynamic)
17. [17-metrics-alerting](modules/17-metrics-alerting) — Метрики и алертинг (Prometheus + Grafana + Alertmanager)
18. [18-logs-tracing](modules/18-logs-tracing) — Централизованное логирование (Loki + Promtail)
19. [19-crd-operators](modules/19-crd-operators) — CRD и операторы (расширение Kubernetes API)
20. [20-batch-workflows](modules/20-batch-workflows) — Батч-нагрузки и workflows (Job parallelism, Indexed, podFailurePolicy, CronJob)
21. [21-stateful-systems](modules/21-stateful-systems) — Базы данных и Stateful-системы (CloudNativePG)
22. [22-ingress-tls](modules/22-ingress-tls) — Ingress и TLS (маршрутизация L7 + HTTPS + cert-manager)
23. [23-gateway-api](modules/23-gateway-api) — Gateway API (преемник Ingress: HTTPRoute, traffic splitting, TLS)
24. [24-progressive-delivery](modules/24-progressive-delivery) — Progressive Delivery (Canary с Argo Rollouts)
25. [25-gitops-at-scale](modules/25-gitops-at-scale) — GitOps на масштабе (Kustomize overlays, ApplicationSet, multi-env)
29. [29-pod-lifecycle-v2](modules/29-pod-lifecycle-v2) — Жизненный цикл пода v2 (native sidecars, scheduling gates, in-place resize)

## 🏗 Итоговые проекты (Capstone)

- [Project A: Platform Namespace](projects/project-a-platform-namespace) — Сборка базового namespace
- [Project B: Stateful Service](projects/project-b-stateful-service) — Деплой stateful-сервиса с БД
- [Project D: Production Readiness Audit](projects/project-d-production-readiness) — Аудит прод-готовности приложения
- [Project E: Secure Multi-Tenant Platform](projects/project-e-secure-platform) — Защищённая мульти-тенант платформа
- [Project F: Incident Response (broken-cluster-lab)](projects/project-c-broken-cluster-lab) — Диагностика и устранение инцидентов

## ✅ QA и Верификация

Для каждого модуля/проекта доступен скрипт верификации:
```bash
./scripts/qa/run-module.sh modules/01-kubectl-basics
```

Массовый прогон всех тестов (regression suite):
```bash
./scripts/qa/sweep.sh
```

## 📂 Структура репозитория

- `docs/` — Базовые документы, чеклисты, справочники (playbooks, cheatsheets), а также [Глоссарий терминов](docs/03-glossary.md).
- `scripts/` — Скрипты инициализации (bootstrap), очистки и QA-верификации.
- `common/` — Общие ресурсы для лаборатории (базовые namespace, квоты и т.д.).
- `modules/` — Директории учебных модулей (теория, манифесты, практические сломанные сценарии).
- `projects/` — Итоговые практические проекты.

## 🛠 Профиль для лёгких нод (2GB)

Если вы работаете на ограниченных ресурсах:
```bash
./scripts/bootstrap/02-install-metrics-server.sh
./scripts/bootstrap/03-install-ingress.sh
./scripts/bootstrap/04-apply-2gb-profile.sh
```
