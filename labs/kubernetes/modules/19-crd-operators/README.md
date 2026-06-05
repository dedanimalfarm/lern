# Лабораторная работа 19: CRD и операторы (расширение Kubernetes API)

> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 и Трек 3

Цель: понять, как Kubernetes из «оркестратора контейнеров» превращается в
платформу — через CustomResourceDefinition (свои типы ресурсов) и оператор-паттерн
(CRD + контроллер). К концу модуля вы регистрируете свой ресурс со схемой и
валидацией и понимаете, что делает оператор на реальном примере
(prometheus-operator из модуля 17).

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

---

## Часть 1: CustomResourceDefinition

### Теория для изучения перед частью

- **CRD** регистрирует НОВЫЙ тип ресурса в API-сервере. После этого он работает
  как встроенный: `kubectl get/apply/describe`, RBAC, watch, etcd-хранение — всё
  бесплатно.
- Идентификация: `group` (`lab.example.com`) + `version` (`v1`) + `kind`
  (`WebApp`). `scope`: `Namespaced` или `Cluster`.
- CRD — фундамент «Kubernetes как платформа»: операторы, GitOps-инструменты,
  service mesh — все добавляют свои CRD.

**Версионирование CRD** (`spec.versions[]` — у нас одна `v1`, но их может быть много):

| Поле версии | Что значит |
|-------------|------------|
| `served: true` | версия ОТДАЁТСЯ через API (можно `get/apply` по этому `apiVersion`) |
| `storage: true` | в КАКОМ формате CR лежит в etcd. **Ровно ОДНА** версия = storage |
| `deprecated: true` (+`deprecationWarning`) | версия помечена устаревшей — kubectl печатает warning |

```yaml
# наш crd.yaml: одна версия, она же и served, и storage
versions:
- name: v1
  served: true
  storage: true       # <- единственное хранилище
```

> При нескольких версиях (v1alpha1 → v1) одна — `storage`, остальные — только
> `served`, а между ними нужна **conversion**-стратегия (`spec.conversion`:
> `None` если поля совместимы, или `Webhook` для нетривиальной конвертации).
> Так API эволюционирует без поломки старых клиентов.

---

**Цель:** зарегистрировать тип `WebApp`.

**Ресурс:** `manifests/crd.yaml`.

---

### 1.1 Регистрация CRD

```bash
kubectl apply -f manifests/crd.yaml
kubectl get crd webapps.lab.example.com
# NAME                       CREATED AT
# webapps.lab.example.com    ...

# Новый ресурс виден в API наравне со встроенными:
kubectl api-resources | grep -i webapp
# webapps   wa   lab.example.com/v1   true   WebApp
```

**Контрольные вопросы:**
1. Что даёт CRD и что появляется «бесплатно» после регистрации?
2. Из чего складывается идентификатор ресурса (group/version/kind)?
3. Почему CRD называют фундаментом «Kubernetes как платформа»?

---

## Часть 2: Custom Resources и схема

### Теория для изучения перед частью

- Экземпляр CRD — **Custom Resource (CR)**. Валидируется по `openAPIV3Schema`:
  типы полей, `required`, `minimum`/`maximum`, паттерны — apiserver отклоняет
  несоответствие на admission.
- Полезное в CRD: `additionalPrinterColumns` (колонки в `kubectl get`),
  `subresources.status` (отдельный `/status`), `subresources.scale` (`kubectl scale`),
  `shortNames`, `categories` (попадание в `kubectl get all`).

**Схема — это и есть валидация (фрагмент нашего `crd.yaml`):**

```yaml
openAPIV3Schema:
  type: object
  properties:
    spec:
      type: object
      required: ["image", "replicas"]   # без них apply ОТКЛОНЯЕТСЯ ("Required value")
      properties:
        image:    { type: string }
        replicas: { type: integer, minimum: 1, maximum: 10 }   # 99 -> "Invalid value: should be <= 10"
        host:     { type: string }
    status:                              # пишется контроллером, не пользователем
      type: object
      properties: { availableReplicas: { type: integer } }
```

- **Server-side pruning (структурные схемы, `apiextensions.k8s.io/v1`).** Поля CR,
  которых НЕТ в схеме, apiserver МОЛЧА ВЫРЕЗАЕТ при сохранении (не просто
  игнорирует — их не будет в etcd). Это защищает от опечаток (`replcas: 3` не
  «потеряется тихо», а исчезнет — и валидация `required` поймает отсутствие
  `replicas`). Чтобы РАЗРЕШИТЬ произвольные поля в поддереве — явно
  `x-kubernetes-preserve-unknown-fields: true`.

#### CEL-валидация (`x-kubernetes-validations`) — без webhook'ов

`minimum`/`maximum`/`required` проверяют ОДНО поле. Кросс-полевые правила («min ≤
max», «host обязателен, если ingress включён») раньше требовали admission-webhook.
С k8s 1.29 (GA) их пишут прямо в схеме на **CEL** (Common Expression Language):

```yaml
properties:
  spec:
    type: object
    properties:
      minReplicas: { type: integer }
      maxReplicas: { type: integer }
    x-kubernetes-validations:
    - rule: "self.minReplicas <= self.maxReplicas"      # self = текущий объект (spec)
      message: "minReplicas must be <= maxReplicas"      # текст в ошибке apply
```

**Reality (проверено на нашем 1.36):**
```bash
# BAD: min=5 > max=2
kubectl apply -f bad-cr.yaml
# The CelTest "bad" is invalid: spec: Invalid value: minReplicas must be <= maxReplicas
# GOOD: min=1 <= max=3  -> celtest/good created
```

- **`self`** — валидируемый узел; `oldSelf` доступен в transition-правилах (с
  `optionalOldSelf`) для проверки «поле нельзя уменьшать». `messageExpression` —
  динамическое сообщение через CEL.
- **Плюс над webhook:** ноль инфраструктуры (нет пода-вебхука, сертификата,
  `ValidatingWebhookConfiguration`), правило живёт в самом CRD, выполняется
  apiserver синхронно. Это тот же CEL, что в **ValidatingAdmissionPolicy**
  (модуль 14) — но привязан к схеме конкретного CRD.
- **Граница:** CEL валидирует объект в момент записи (без обращения к другим
  ресурсам и внешним системам) — для «проверить, что Deployment с таким именем уже
  есть» по-прежнему нужен webhook/контроллер.

---

**Цель:** создать CR и увидеть валидацию.

**Ресурсы:** `manifests/webapp.yaml`, `broken/scenario-01/bad-webapp.yaml`.

---

### 2.1 Создать CR и проверить схему

```bash
kubectl apply -f manifests/webapp.yaml
kubectl -n lab get webapp           # или: kubectl -n lab get wa
# NAME        IMAGE              REPLICAS   AGE
# my-webapp   nginx:1.27-alpine  3          5s     <- additionalPrinterColumns

# Невалидный CR отклоняется СХЕМОЙ (admission), не создаётся:
kubectl apply -f broken/scenario-01/bad-webapp.yaml
# error: ... spec.replicas: Invalid value: 99: ... should be <= 10
#        spec.image: Required value
```

> Валидацию вы получили, лишь описав схему — без единой строки кода контроллера.

**Контрольные вопросы:**
1. Где описывается валидация CR и на каком этапе она срабатывает?
2. Что дают `additionalPrinterColumns` и `subresources.status`?
3. Зачем `shortNames` и `categories`?

---

## Часть 3: Operator pattern

### Теория для изучения перед частью

- CRD сам по себе — лишь «запись в базе»: создав `WebApp`, вы НЕ получите поды.
  Чтобы CR что-то ДЕЛАЛ, нужен **контроллер** — программа с reconcile-циклом:
  «увидел желаемое (CR) → привёл фактическое к нему → записал status».
- **CRD + контроллер = оператор.** Операторы инкапсулируют эксплуатационные
  знания (как развернуть/бэкапить/обновить БД и т.п.).

**Reconcile loop по шагам** (что делал бы контроллер WebApp):

```
   watch WebApp/Deployment ──> очередь ──> Reconcile(ns/name):
        │                                      │
        │   1. observe DESIRED: прочитать CR WebApp (spec.image, spec.replicas)
        │   2. observe ACTUAL:  есть ли уже Deployment <name>? какой у него стейт?
        │   3. diff:            spec.replicas=3, а Deployment=1  → расхождение
        │   4. act (идемпотентно): create/update Deployment под spec (3 реплики)
        │   5. write STATUS:    status.availableReplicas = факт (subresource /status)
        └────────────── повтор на КАЖДОЕ изменение CR или managed-ресурса ◄──┘
```

- **Идемпотентность + level-triggered.** Reconcile вызывается на ЛЮБОЕ изменение и
  должен давать тот же итог независимо от того, сколько раз вызван и что было
  раньше (реагирует на ТЕКУЩЕЕ состояние = level, а не на «событие» = edge). Поэтому
  потеря события не страшна — следующий reconcile всё выровняет.
- **ownerReferences.** Контроллер ставит на созданный Deployment `ownerReference`
  на свой WebApp. Тогда удаление WebApp каскадно удаляет Deployment (garbage
  collector по owner-цепочке) — без ручной уборки. (Так же `Deployment`→`ReplicaSet`
  →`Pod` из модуля 03.)
- **finalizers.** Если при удалении CR нужно прибрать ВНЕШНЕЕ (облачный LB, запись в
  СУБД), контроллер вешает на CR `finalizer`. Тогда `delete` лишь ставит
  `deletionTimestamp`, объект «висит» `Terminating`, пока контроллер не сделает
  cleanup и не СНИМЕТ finalizer — только потом apiserver реально удаляет CR.

---

**Цель:** увидеть реальный оператор на кластере.

---

### 3.1 prometheus-operator как пример

```bash
# CRD, которыми управляет prometheus-operator (из модуля 17):
kubectl get crd | grep monitoring.coreos.com
# alertmanagers / prometheuses / servicemonitors / prometheusrules ...

# Сам контроллер-оператор:
kubectl -n monitoring get pods | grep operator
# kps-kube-prometheus-stack-operator-...   Running

# Когда вы создаёте ServiceMonitor (CR), оператор РЕАГИРУЕТ — перенастраивает
# Prometheus. Это reconcile в действии (вы это видели в модуле 17).
```

### 3.2 Свой контроллер для WebApp (reconcile вживую)

CRD `WebApp` сам по себе ничего не разворачивает. Сделаем его «живым»: учебный
контроллер `controller/app-controller.sh` (reconcile-петля на `kubectl`+`jq`, без
kopf/controller-runtime) для каждого `WebApp X` создаёт `Deployment X-deploy`
(образ/реплики из `spec`) + `Service X-svc`, пишет `status.availableReplicas`, а на
созданные объекты вешает `ownerReferences` → их КАСКАДНО снесёт GC при удалении CR.

```bash
# 1) Запустить контроллер на control-машине (использует текущий KUBECONFIG)
bash controller/app-controller.sh &          # Ctrl+C / kill — остановить
#    [webapp-controller] reconciled my-webapp: my-webapp-deploy(replicas=3,...) + my-webapp-svc

# 2) Создать новый CR — контроллер сам развернёт Deployment+Service
kubectl apply -f - <<'EOF'
apiVersion: lab.example.com/v1
kind: WebApp
metadata: { name: test-webapp, namespace: lab }
spec: { replicas: 2, image: nginx:alpine }
EOF
kubectl -n lab get deploy test-webapp-deploy svc/test-webapp-svc    # появились сами
kubectl -n lab get webapp test-webapp -o jsonpath='{.status.availableReplicas}{"\n"}'  # контроллер пишет status

# 3) Изменить spec — reconcile применит к Deployment (level-triggered)
kubectl -n lab patch webapp test-webapp --type=merge -p '{"spec":{"replicas":3}}'
kubectl -n lab get deploy test-webapp-deploy -w     # реплики -> 3

# 4) Удалить CR — Deployment и Service уйдут САМИ (ownerReferences -> GC)
kubectl -n lab delete webapp test-webapp
kubectl -n lab get deploy,svc -l app=test-webapp    # пусто
```

> ✅ **Прогнано на Kubespray:** create → `test-webapp-deploy`(2)+`test-webapp-svc`;
> `replicas:3` → масштаб до 3; смена `image` → обновился Deployment; delete CR →
> deploy+svc снесены каскадно (через `ownerReferences`, см. теорию 3.x). Это и есть
> оператор-паттерн в миниатюре. **Прод-версия:** запускать контроллер как Pod в
> кластере с ServiceAccount+RBAC (на `webapps`,`deployments`,`services`) и
> использовать `--watch`/informers вместо poll; писать на Go (controller-runtime/
> Kubebuilder) или Python (kopf).

> 🏭 **Прод-реализация в этом же модуле:** `controller/webapp_controller.py` —
> тот же оператор на Python (informers + workqueue + resync, client `kubernetes`),
> упакованный в контейнер (`controller/Dockerfile`, non-root) и разворачиваемый
> как Pod с least-privilege RBAC: `kubectl apply -k controller/manifests/`
> (ns `webapp-operator` + SA + ClusterRole на webapps/deployments/services +
> sample WebApp). Это «как в реальности», bash-версия выше — для понимания петли.

**Контрольные вопросы:**
1. Чем CRD без контроллера отличается от оператора?
2. Что такое reconcile loop и какие три шага он делает?
3. Как `ownerReferences` обеспечивают удаление Deployment/Service при удалении CR?
4. Приведите два реальных оператора и что они автоматизируют.

---

## Часть 4: kubectl и кастомные ресурсы

```bash
kubectl -n lab get wa -o wide                  # short name
kubectl -n lab get webapp my-webapp -o yaml | grep -A3 spec
kubectl -n lab describe webapp my-webapp
kubectl api-resources --api-group=lab.example.com
```

**Контрольные вопросы:**
1. Как сделать так, чтобы CR попадал в `kubectl get all`?
2. Зачем `status` как отдельный subresource (кто его пишет)?
3. Как посмотреть все ресурсы вашей API-группы?

---

## Часть 5: Troubleshooting

### Теория: методология диагностики CRD/CR

Проблемы делятся на три слоя — определи слой, тогда ясна команда:

```
Что не так?
 ├─ CR не СОЗДАЁТСЯ (apply падает)
 │     ├─ "Invalid value" / "Required value"  -> СХЕМА (openAPIV3Schema): чини CR под required/min/max
 │     └─ "no matches for kind WebApp"          -> CRD не применён / не та group-version
 │            kubectl get crd | grep example.com ; kubectl api-resources --api-group=lab.example.com
 │
 ├─ CR создан, но НИЧЕГО НЕ ПРОИСХОДИТ (нет подов)
 │     -> это норма БЕЗ контроллера: CRD = только запись. Нужен оператор (Часть 3).
 │        Если оператор есть: смотри ЕГО логи и status CR:
 │        kubectl -n lab get webapp my-webapp -o jsonpath='{.status}' ; kubectl logs <operator-pod>
 │
 └─ CR не УДАЛЯЕТСЯ (висит Terminating)
       -> finalizer не снят (контроллер мёртв/не дочистил внешнее):
          kubectl get webapp my-webapp -o jsonpath='{.metadata.finalizers}'
          (крайняя мера — убрать finalizer вручную: kubectl patch ... -p '{"metadata":{"finalizers":[]}}' --type=merge)
```

---

### Инцидент 1: CR отклонён схемой

Разобран в `broken/scenario-01/`. Симптом: `apply` падает с `Invalid value` /
`Required value`. Диагностика — прочитать ошибку (поле + правило), привести CR в
соответствие схеме CRD. Профилактика: писать строгие схемы (required/min/max),
ловить ошибки на admission, а не в рантайме контроллера.

### Инцидент 2: `kubectl get <kind>` — «not found»

```bash
# Причины: CRD не применён, неверная group/version, опечатка в kind.
kubectl get crd | grep example.com           # есть ли CRD
kubectl api-resources | grep -i webapp        # под каким group/version
# apiVersion в CR должен быть lab.example.com/v1 (group/version из CRD).
```

**Контрольные вопросы:**
1. Как из ошибки валидации понять, ЧТО нарушено?
2. `kubectl get webapp` пишет «not found» — три причины?
3. Где взять правильный `apiVersion` для своего CR?

---

## Проверка модуля

```bash
kubectl apply -f manifests/crd.yaml
kubectl apply -f manifests/webapp.yaml

bash verify/verify.sh
# [OK] CRD WebApp registered + my-webapp instance exists
# [OK] module 19 verified
```

`verify.sh`: namespace `lab` → CRD `webapps.lab.example.com` зарегистрирована →
экземпляр `my-webapp` существует.

---

## Финальная карта ресурсов модуля

| Ресурс | Что демонстрирует |
|--------|-------------------|
| `webapps.lab.example.com` (CRD) | расширение API своим типом + схема/валидация |
| `my-webapp` (CR) | экземпляр кастомного ресурса, printer columns |
| `bad-webapp` (broken) | отклонение по схеме (admission) |
| prometheus-operator (внешний) | реальный оператор (CRD + reconcile) |

---

## Теоретические вопросы (итоговые)

1. Что регистрирует CRD и что появляется автоматически после этого?
2. Версии CRD: чем `served` отличается от `storage` и сколько может быть каждой?
3. Где и как валидируется Custom Resource? Что делает server-side pruning с полем,
   которого нет в схеме?
4. Чем CRD без контроллера отличается от оператора?
5. Опишите reconcile loop по шагам. Что значит «идемпотентный, level-triggered»?
6. Зачем `ownerReferences` (каскадное удаление) и `finalizers` (Terminating)?
7. Зачем нужны `subresources.status`/`scale` и `additionalPrinterColumns`?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Создайте CR с нарушением схемы (replicas=99 / без image) и прочитайте отказ admission.
2. Докажите server-side pruning: добавьте в CR поле вне схемы и убедитесь, что оно вырезано.
3. Запустите учебный контроллер (`controller/app-controller.sh`) и проверьте reconcile: создайте WebApp → появились Deployment+Service.
4. Обновите `spec.replicas` у WebApp и убедитесь, что контроллер масштабировал Deployment.
5. Удалите WebApp и подтвердите каскадное удаление Deployment/Service через `ownerReferences`.

---

## Шпаргалка

```bash
# === CRD ===
kubectl apply -f manifests/crd.yaml
kubectl get crd | grep example.com
kubectl api-resources --api-group=lab.example.com

# === Custom Resources ===
kubectl -n lab apply -f manifests/webapp.yaml
kubectl -n lab get wa -o wide
kubectl -n lab get webapp my-webapp -o yaml

# === реальные операторы на кластере ===
kubectl get crd | grep -E "monitoring.coreos.com|cert-manager|argoproj"
kubectl get pods -A | grep -i operator

# === Уборка ===
kubectl -n lab delete -f manifests/webapp.yaml
kubectl delete crd webapps.lab.example.com   # удаляет CRD И все его CR
```

---

## Уборка

```bash
kubectl -n lab delete -f manifests/webapp.yaml --ignore-not-found
kubectl delete crd webapps.lab.example.com --ignore-not-found
```
