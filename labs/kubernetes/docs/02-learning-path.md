# Карта обучения (Learning Path)

Эта страница описывает рекомендуемые треки прохождения лаборатории по Kubernetes.
Все модули разделены на тематические треки, для каждого указана оценка времени прохождения (в минутах) и сложность (от 1 до 5).

## Треки обучения

### 1. Основы Kubernetes (Core)
Идеально для начинающих. Закладывает фундамент работы с кластером. Пререквизиты: базовое знание Linux и Docker.
* **[01-kubectl-basics](../modules/01-kubectl-basics)** (15 мин, сложность 1/5)
* **[02-pods-lifecycle](../modules/02-pods-lifecycle)** (20 мин, сложность 2/5)
* **[03-workloads](../modules/03-workloads)** (25 мин, сложность 2/5)
* **[04-networking](../modules/04-networking)** (30 мин, сложность 3/5)
* **[05-storage](../modules/05-storage)** (25 мин, сложность 2/5)
* **[06-scheduling](../modules/06-scheduling)** (20 мин, сложность 2/5)
* **[07-config-security](../modules/07-config-security)** (20 мин, сложность 2/5)

### 2. Эксплуатация и Наблюдаемость (Operations & Observability)
Для тех, кто хочет понимать, как кластер работает внутри и как мониторить сервисы. Пререквизиты: Трек 1 (Core).
* **[08-observability](../modules/08-observability)** (20 мин, сложность 2/5)
* **[10-kubeadm-admin](../modules/10-kubeadm-admin)** (30 мин, сложность 4/5)
* **[17-metrics-alerting](../modules/17-metrics-alerting)** (30 мин, сложность 3/5)
* **[18-logs-tracing](../modules/18-logs-tracing)** (25 мин, сложность 3/5)
* **[20-batch-workflows](../modules/20-batch-workflows)** (20 мин, сложность 3/5)
* **[Project F: Incident Response](../projects/project-c-broken-cluster-lab)** (45 мин, сложность 5/5) — *Capstone*

### 3. Продвинутая поставка (Delivery & Resilience)
Для инженеров CI/CD и платформы. Учимся выкатывать сервисы надёжно и без даунтаймов. Пререквизиты: Трек 1 (Core).
* **[09-helm-gitops](../modules/09-helm-gitops)** (25 мин, сложность 2/5)
* **[11-autoscaling](../modules/11-autoscaling)** (25 мин, сложность 3/5)
* **[12-resource-management](../modules/12-resource-management)** (20 мин, сложность 3/5)
* **[13-resilience](../modules/13-resilience)** (20 мин, сложность 3/5)
* **[21-stateful-systems](../modules/21-stateful-systems)** (35 мин, сложность 4/5)
* **[22-ingress-tls](../modules/22-ingress-tls)** (30 мин, сложность 4/5)
* **[25-gitops-at-scale](../modules/25-gitops-at-scale)** (30 мин, сложность 4/5)

### 4. Безопасность и Расширения (Security & Extensions)
Для специалистов по безопасности (DevSecOps) и разработки операторов. Пререквизиты: Трек 1 и Трек 3.
* **[14-pod-security-admission](../modules/14-pod-security-admission)** (25 мин, сложность 3/5)
* **[15-network-policy-enforced](../modules/15-network-policy-enforced)** (25 мин, сложность 4/5)
* **[16-secrets-management](../modules/16-secrets-management)** (25 мин, сложность 3/5)
* **[19-crd-operators](../modules/19-crd-operators)** (30 мин, сложность 4/5)

## Итоговые проекты (Capstone)
Проекты служат для закрепления пройденного материала.
* **[Project A: Platform Namespace](../projects/project-a-platform-namespace)** (20 мин, сложность 2/5) — Сборка базового namespace.
* **[Project B: Stateful Service](../projects/project-b-stateful-service)** (25 мин, сложность 3/5) — Деплой базы данных с persistent-хранилищем.
* **[Project D: Production Readiness](../projects/project-d-production-readiness)** (30 мин, сложность 4/5) — Аудит прод-готовности приложения.
* **[Project E: Secure Multi-Tenant Platform](../projects/project-e-secure-platform)** (45 мин, сложность 5/5) — Разворачивание защищённого мульти-тенант кластера с изоляцией политиками.
* **[Project F: Incident Response](../projects/project-c-broken-cluster-lab)** (45 мин, сложность 5/5) — Триаж и починка сломанного кластера.
