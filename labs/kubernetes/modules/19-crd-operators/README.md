# Лабораторная работа 19: CRD и операторы (расширение Kubernetes API)

Цель: понять, как Kubernetes из «оркестратора контейнеров» превращается в
платформу — через CustomResourceDefinition (свои типы ресурсов) и оператор-паттерн
(CRD + контроллер). К концу модуля вы регистрируете свой ресурс со схемой и
валидацией и понимаете, что делает оператор на реальном примере
(prometheus-operator из модуля 17).

---

## Предварительные требования

```bash
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1
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

**Контрольные вопросы:**
1. Чем CRD без контроллера отличается от оператора?
2. Что такое reconcile loop и какие три шага он делает?
3. Приведите два реальных оператора и что они автоматизируют.

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
2. Где и как валидируется Custom Resource?
3. Чем CRD без контроллера отличается от оператора?
4. Опишите reconcile loop оператора.
5. Зачем нужны `subresources.status`/`scale` и `additionalPrinterColumns`?

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
