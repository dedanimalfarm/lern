# Review: Базовые модули 01-05 (kubectl, pods, workloads, networking, storage)

**Дата:** 2026-06-02
**Кластер:** Kubespray (3 ноды: 1 cp + 2 worker, v1.36.1, Calico CNI)
**Kubeconfig:** `export KUBECONFIG=/root/.kube/kubespray.conf`

---

## Executive Summary

Все 5 модулей имеют единообразную архитектуру (5 частей: теория → практика → контрольные вопросы → troubleshooting → verify) и следуют шаблону `manifests/ + tasks/ + broken/ + solutions/ + verify/`. Глубина модулей **неравномерна**: lab01 (826 строк, эталон) и lab05 (850 строк, самый детальный) заметно опережают lab02 (645), lab03 (587) и lab04 (497 — самый короткий).

**Главный блокер:** на кластере НЕТ StorageClass → модули 03 (StatefulSet) и 05 (всё PVC/PV/StatefulSet) не заработают без предварительной настройки кластера. Также нет Ingress Controller для модуля 04.

---

## 1. Cluster Readiness Assessment

### Что есть
| Компонент | Статус | Детали |
|-----------|--------|--------|
| Calico CNI | ✅ | NetworkPolicy enforcement работает |
| CoreDNS | ✅ | nodelocaldns + coredns, 2 реплики |
| kube-prometheus-stack | ✅ | monitoring ns, Grafana + Prometheus + Alertmanager |
| Namespace `lab` | ✅ | Уже содержит ресурсы от других тестов |
| Namespace `lab-restricted` | ✅ | Для NetworkPolicy-тестов |

### Что ОТСУТСТВУЕТ (блокеры)
| Компонент | Impact | Модули затронуты |
|-----------|--------|-----------------|
| **StorageClass** | 🔴 Критический | 03 (StatefulSet), 05 (все PVC/PV/STS) |
| **Ingress Controller** | 🔴 Критический | 04 (Ingress-часть) |
| **CSI Drivers** | 🟡 Средний | 05 (динамическое provisioning) |
| **VolumeSnapshotClass** | 🟢 Низкий | 05 (не входит в скоуп) |
| **metrics-server** | 🟡 Средний | 02 (kubectl top pod) |

### Ресурсы в namespace `lab` (уже существуют)
```
deployment.apps/resilient-app    3 реплики nginx:1.27-alpine
webapp.lab.example.com/my-webapp  (CRD? кастомный ресурс)
```
Рекомендация: перед прогоном модуля сносить предыдущие ресурсы или использовать `kubectl delete -k manifests/`.

---

## 2. Per-Module Deep Review

### Модуль 01: kubectl-basics (826 строк) — ЭТАЛОН

**Структура:** 5 частей, контрольные вопросы после каждой, финальная таблица, 4 блока × 3 вопроса = 12 вопросов, шпаргалка.

**Сильные стороны:**
- API-центричная модель (`kubectl -v=6`, `api-resources`, `explain`) — уникальная тема, не повторяется в других модулях
- Полная цепочка Deployment → ReplicaSet → Pod → Service → Endpoints → DNS
- Цикл диагностики (get → describe → logs → exec → port-forward) с примерами
- Troubleshooting: 3 инцидента (более глубоко, чем 1 сценарий в broken/)

**Проблемы:**
- `broken/scenario-01/deploy.yaml`: отсутствуют `resources` и `securityContext` (ок для broken-формата, но solution тоже их не добавляет)
- `solutions/01-wrong-port/deploy.yaml`: не соответствует эталонному `manifests/app/deploy.yaml` по набору полей

**Оценка:** ⭐⭐⭐⭐⭐ — эталон, менять нечего (только синхронизировать solution с main-манифестом).

---

### Модуль 02: pods-lifecycle (645 строк, −22% vs эталон)

**Структура:** 5 частей, контрольные вопросы, финальная таблица, 4 блока × 3 вопроса = 12 вопросов, шпаргалка.

**Сильные стороны:**
- Часть 1 (фазы Pod): подробный разбор Pending/Running/Succeeded/Failed/Unknown с причинами
- Init-контейнеры: практический пример с ожиданием DNS и передачей файла через emptyDir
- Probes: различие readiness/liveness по последствиям хорошо объяснено
- OOMKilled/exitCode 137: отличный hands-on пример с `polinux/stress`

**Гапы (что добавить):**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | `startupProbe` — только фрагмент YAML | Добавить полноценное упражнение 3.4: Pod с медленным стартом, сравнение поведения с/без startupProbe |
| **HIGH** | `preStop` hook — упомянут в теории, нет практики | Добавить короткое упражнение: Pod с `preStop` и sleep-задержкой, наблюдение graceful shutdown через `kubectl delete pod --grace-period` |
| **MED** | `terminationGracePeriodSeconds` | Добавить в Часть 1: показать разницу между 0s (force kill) и 30s (graceful) |
| **MED** | `postStart` hook | Упомянуть как аналог init (но асинхронный), пример с нотификацией |
| **LOW** | ephemeral containers (`kubectl debug`) | Бонус в troubleshooting: как заглянуть в контейнер без shell |

**Проблемы манифестов:**
- `manifests/probes/svc.yaml`: не указан `type: ClusterIP` явно (мелкий стилистический разнос с lab01/lab04)
- `solutions/02-readiness-fail/deploy.yaml`: нет `resources` и `securityContext`

**Verify.sh:** проверяет init-контейнер и probes, но не проверяет их значения (только наличие). Можно усилить: проверить, что путь пробы = `/`.

**Оценка:** ⭐⭐⭐⭐ — хорошая база, но не хватает глубины в startupProbe и graceful shutdown.

---

### Модуль 03: workloads (587 строк, −29% vs эталон)

**Структура:** 5 частей, контрольные вопросы, финальная таблица + бонус «Когда какой контроллер», 4 блока × 2-3 вопроса = 11 вопросов, шпаргалка + cleanup.

**Сильные стороны:**
- Deployment rollout: v1→v2 с `change-cause` аннотацией, история ревизий, rollback
- Job/CronJob: backoffLimit, concurrencyPolicy, ручной триггер из CronJob
- DaemonSet: проверка DESIRED = числу нод
- Таблица «Когда какой контроллер» — отличный итоговый артефакт
- Cleanup-секция (единственный модуль, где это выделено явно)

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | StatefulSet PVC lifecycle | Добавить: scale down → PVC остаются, scale up → переиспользуются; `persistentVolumeClaimRetentionPolicy` (k8s ≥ 1.27) |
| **HIGH** | StatefulSet update strategies | Добавить: `OnDelete` vs `RollingUpdate`, partition для канареечного обновления |
| **MED** | ReplicaSet — контроллер за кулисами | Добавить в Часть 1: `kubectl get rs`, сравнение старых/новых ReplicaSet, связь `ownerReferences` |
| **MED** | PodDisruptionBudget | Бонус уже есть, но только текстом. Добавить `pdb.yaml` манифест и проверку через `kubectl drain --dry-run` |
| **LOW** | `kubectl scale` vs изменение `replicas` | Разница между императивным и декларативным масштабированием |
| **LOW** | `kubectl set image` vs `apply` | Когда что использовать для обновления образа |

**Проблемы манифестов:**
- `solutions/01-imagepull/deploy.yaml`: 1 реплика вместо 2 (в main v1), нет probes/resources/securityContext
- `manifests/deployment/v1/svc.yaml`: не указан `type: ClusterIP` явно
- `manifests/statefulset/sts.yaml`: нет `storageClassName` → зависит от дефолтного SC (которого нет)

**Verify.sh:** НЕ проверяет StatefulSet `web` и headless Service `web`. Это СУЩЕСТВЕННЫЙ гап — студент может пропустить всю часть 4.

**Оценка:** ⭐⭐⭐½ — хороший охват контроллеров, но StatefulSet-часть недостаточно глубока, verify.sh пропускает важный ресурс.

---

### Модуль 04: networking (497 строк, −40% vs эталон — САМЫЙ КОРОТКИЙ)

**Структура:** 5 частей, контрольные вопросы, финальная таблица, 4 блока × 2-3 вопроса = 11 вопросов, шпаргалка + cleanup.

**Сильные стороны:**
- Service/Endpoints: чёткая связь selector→Endpoints→kube-proxy
- NodePort: готовый манифест с портом 30080
- NetworkPolicy: default-deny + allow-dns + allow-app, проверка enforcement (Calico)
- Привязка к реальному кластеру: «Проверено на нашем Kubespray-кластере (Calico)»
- Cleanup: правильный порядок удаления (сначала NetworkPolicy)

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | Ingress Controller установка | Добавить инструкцию по установке ingress-nginx на Kubespray (helm или raw manifests). Без этого Ingress — «сухой» объект без адреса. |
| **HIGH** | DNS-практика: поиск по короткому имени | Добавить упражнение: `nslookup net-demo` (без полного FQDN) vs `nslookup net-demo.lab` — демонстрация search domains |
| **HIGH** | EndpointSlices | Упомянуть (k8s ≥ 1.21 заменяют большие Endpoints), `kubectl get endpointslices` |
| **MED** | kube-proxy mode: iptables vs IPVS | Добавить в теорию Части 1: как узнать текущий режим на кластере |
| **MED** | NetworkPolicy: ipBlock (разрешить внешний CIDR) | Добавить пример в 4.2: разрешить egress к внешнему API |
| **MED** | `externalTrafficPolicy: Local` | Добавить в NodePort: почему без него source IP теряется |
| **LOW** | Ingress: TLS (cert-manager) | Упомянуть в теории, что Ingress умеет TLS, но без cert-manager сертификатами управлять вручную |
| **LOW** | Multus / доп. сети | За горизонтом базового модуля, но упомянуть в «что дальше» |

**Проблемы манифестов:**
- `manifests/nodeport/svc-nodeport.yaml`: не хватает `externalTrafficPolicy` (по умолчанию Cluster — source IP теряется)
- `solutions/01-selector-mismatch/svc.yaml`: не указан `type: ClusterIP`
- Ingress: `ingressClassName: nginx` — класс не существует на кластере (объект создастся, но без адреса)

**Verify.sh:** НЕ проверяет:
- NodePort service `net-demo-nodeport`
- NetworkPolicy: `default-deny`, `allow-dns`, `allow-app-ingress`
- Это СУЩЕСТВЕННЫЙ гап — основные ресурсы модуля не верифицируются.

**Оценка:** ⭐⭐⭐ — адекватный охват тем, но сильно недобирает по глубине (особенно DNS и Ingress). Самый короткий модуль при очень широкой теме.

---

### Модуль 05: storage (850 строк, +3% vs эталон — САМЫЙ ДЛИННЫЙ)

**Структура:** 4 части, контрольные вопросы, финальная таблица (с колонкой «Часть»), 5 блоков × вопросов = 20 вопросов (!), шпаргалка + cleanup.

**Сильные стороны:**
- Самый детальный модуль: 20 теоретических вопросов против 11-12 в остальных
- Troubleshooting: 3 инцидента + бонусный diagnostic-скрипт
- PV/PVC: и статическое, и динамическое provisioning
- accessModes: RWO/ROX/RWX/RWOP с объяснением когда что
- volumeBindingMode: Immediate vs WaitForFirstConsumer
- reclaimPolicy: Delete vs Retain с практикой
- Multi-Attach error: объяснение причины и архитектурного решения
- StatefulSet + volumeClaimTemplates: глубокое покрытие
- Ручное переиспользование Released PV: `kubectl patch pv`

**Гапы:**

| Приоритет | Тема | Что сделать |
|-----------|------|-------------|
| **HIGH** | StorageClass создание | Добавить Часть 0: «Подготовка кластера» — как установить `local-path-provisioner` на Kubespray (ранчеровский local-path-provisioner — де-факто стандарт для учебных кластеров) |
| **HIGH** | `persistentVolumeClaimRetentionPolicy` | StatefulSet с `whenDeleted: Retain` / `whenScaled: Delete` (k8s 1.27+) |
| **MED** | Расширение тома (volume expansion) | Практический пример: `kubectl patch pvc` с увеличением storage, проверка на кластере |
| **MED** | CSI Snapshot и Restore | Упомянуть как продвинутую тему, ссылка на документацию |
| **MED** | `emptyDir.medium: Memory` | tmpfs-вариант emptyDir, пример с RAM-диском |
| **MED** | `hostPath` риски безопасности | Добавить предупреждение о PodSecurityPolicy/PSA, пример когда hostPath даёт побег из контейнера |
| **LOW** | generic ephemeral volumes (k8s 1.23+) | Упомянуть inline CSI-тома как альтернативу emptyDir |
| **LOW** | `ReadWriteOncePod` (k8s 1.22+) | Когда RWO недостаточно и нужен RWOP |

**Проблемы манифестов:**
- `manifests/statefulset/svc-headless.yaml`: port name `tcp` вместо `http` (в module 03 — `http`) — стилистический разнос
- `manifests/pvc/pvc.yaml`: нет `storageClassName` — подразумевает default (которого нет)
- `manifests/statefulset/sts.yaml`: нет `storageClassName` — та же проблема
- `broken/scenario-01/pvc.yaml`: использует `storageClassName: does-not-exist` — корректный баг, но если на кластере нет дефолтного SC, то и «рабочий» PVC тоже будет Pending. Это сбивает с толку: какой именно SC должен работать?

**Verify.sh:** НЕ проверяет:
- emptyDir pod `storage-emptydir`
- hostPath pod `storage-hostpath`
- Static PV `static-pv-demo` и PVC `static-pvc-demo`
- `require_storageclass` проверяет наличие ЛЮБОГО SC. Если SC только что создали — ок, но verify должен явно проверять `standard` (или имя SC из конфига).

**Оценка:** ⭐⭐⭐⭐⭐ — самый глубокий модуль, но 4 части вместо 5 (можно разбить Часть 2 на две: «Динамическое provisioning» и «Статическое provisioning»), и необходима документированная процедура создания StorageClass.

---

## 3. Cross-Module Consistency Issues

### 3.1 Стилистические разносы

| Проблема | Где | Исправление |
|----------|-----|-------------|
| `type: ClusterIP` не указан явно | 02-probes/svc.yaml, 03-deployment/v1/svc.yaml, 04-solutions/svc.yaml | Добавить `type: ClusterIP` для консистентности с 01 и 04 |
| Headless port name | 03: `http`, 05: `tcp` | Унифицировать в `http` |
| `kubectl` vs `kubectl -n lab` | Разные модули используют разные подходы | Везде использовать `-n lab` или задать `--namespace` в начале |
| Финальная таблица | 01,02,04: без колонки «Часть»; 05: с колонкой «Часть»; 03: без namespace | Унифицировать колонки: Ресурс, Тип, Namespace, Часть, Что демонстрирует |

### 3.2 Solutions vs Main Manifests

**Системная проблема:** все solution-файлы УПРОЩЕНЫ по сравнению с основными манифестами — отсутствуют `resources`, `securityContext`, probes, `APP_VERSION`. Студент, скопировавший solution, получает менее защищённый деплой.

**Рекомендация:** выровнять solution-файлы до уровня main-манифестов (добавить `resources`, `securityContext`, probes). Либо явно пометить в README: «Solution исправляет ТОЛЬКО целевую проблему; hardening не входит в задачу инцидента».

### 3.3 Verify.sh gaps (сводная)

| Модуль | Пропущенные проверки | Критичность |
|--------|---------------------|-------------|
| 03 | StatefulSet `web`, headless Service `web` | 🔴 HIGH |
| 04 | NodePort `net-demo-nodeport`, все NetworkPolicy (`default-deny`, `allow-dns`, `allow-app-ingress`) | 🔴 HIGH |
| 05 | emptyDir `storage-emptydir`, hostPath `storage-hostpath`, static PV/PVC | 🟡 MED |

---

## 4. Prioritized Action Items

### 🔴 High Priority (блокируют выполнение)

1. **Установить StorageClass на кластер**
   - Установить `rancher/local-path-provisioner`: `kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml`
   - Или Helm: `helm repo add nfs-subdir-external-provisioner ...`
   - Добавить в README модулей 03/05 ссылку на setup-инструкцию
   - Затрагивает: **03 (StatefulSet), 05 (весь модуль)**

2. **Установить Ingress Controller**
   - `helm install ingress-nginx ingress-nginx/ingress-nginx --set controller.hostPort.enabled=true`
   - Или raw-манифесты ingress-nginx
   - Добавить в README модуля 04
   - Затрагивает: **04 (Часть 3 — Ingress)**

3. **Добавить verify-проверки для пропущенных ресурсов**
   - Модуль 03: добавить `require_resource lab svc web` + `require_statefulset_ready lab web`
   - Модуль 04: добавить проверки NodePort и NetworkPolicy

### 🟡 Medium Priority (улучшение глубины)

4. **Модуль 02: полноценное упражнение startupProbe**
   - Заменить «фрагмент» на практический пример с Pod, у которого долгий прогрев (sleep + curl readiness)
   - Добавить `preStop` упражнение

5. **Модуль 03: углубить StatefulSet**
   - Scale down → PVC retention
   - `persistentVolumeClaimRetentionPolicy`
   - OnDelete vs RollingUpdate

6. **Модуль 04: углубить DNS**
   - Практический пример с search domains и короткими именами
   - `ndots:5` и его влияние
   - EndpointSlices

7. **Модуль 05: документировать StorageClass creation**
   - Часть 0 «Подготовка» с установкой local-path-provisioner
   - Или статический PV как fallback (уже есть в `static-pv/`)

8. **Выровнять solution-файлы с main-манифестами**
   - Добавить `resources`, `securityContext`, probes во все solution-файлы
   - ИЛИ добавить явный comment: "This solution fixes ONLY the targeted bug"

### 🟢 Low Priority (косметика и нишевые фичи)

9. **Унифицировать Service type**
   - Добавить `type: ClusterIP` во все сервисы где он подразумевается

10. **Унифицировать порт-нейминг**
    - `tcp` → `http` в модуле 05 headless service

11. **Модуль 04: добавить `externalTrafficPolicy: Local`**
    - В манифест NodePort и пояснение

12. **Модуль 05: `emptyDir.medium: Memory`**
    - Добавить пример tmpfs

13. **Унифицировать колонки в финальных таблицах**

---

## 5. Quick-Win: Cluster Setup Script

Для решения блокеров 1-2 предлагаю создать `/root/lern/labs/kubernetes/scripts/setup-cluster.sh`:

```bash
#!/usr/bin/env bash
# Установка StorageClass и Ingress Controller на Kubespray-кластер

export KUBECONFIG="${KUBECONFIG:-/root/.kube/kubespray.conf}"

echo "=== Installing local-path-provisioner (StorageClass) ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.29/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "=== Installing ingress-nginx ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=ClusterIP \
  --wait --timeout 5m

echo "=== Done ==="
kubectl get sc
kubectl -n ingress-nginx get pods
```

Без выполнения этих двух шагов модули 03, 04 и 05 либо неработоспособны, либо выполняются со значительными ограничениями.

---

## 6. Итоговая таблица модулей

| Модуль | Строк | Частей | Вопросов | Инцидентов | Verify gaps | Оценка |
|--------|-------|--------|----------|------------|-------------|--------|
| 01-kubectl-basics | 826 | 5 | 12 | 3 | — | ⭐⭐⭐⭐⭐ |
| 02-pods-lifecycle | 645 | 5 | 12 | 2 | — | ⭐⭐⭐⭐ |
| 03-workloads | 587 | 5 | 11 | 2+1 | 🔴 STS | ⭐⭐⭐½ |
| 04-networking | 497 | 5 | 11 | 2+1 | 🔴 NP+NPOL | ⭐⭐⭐ |
| 05-storage | 850 | 4 | 20 | 3+1 | 🟡 PV | ⭐⭐⭐⭐⭐ |
