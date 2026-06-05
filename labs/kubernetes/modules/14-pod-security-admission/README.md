# Лабораторная работа 14: Pod Security и Admission Control (PSA + ValidatingAdmissionPolicy)

> ⏱ время ~25 мин · сложность 3/5 · пререквизиты: Трек 1 и Трек 3

Цель: научиться запрещать небезопасные поды НА ВХОДЕ (admission), пока они не
попали в кластер — через встроенный Pod Security Admission (профили
privileged/baseline/restricted) и ValidatingAdmissionPolicy (кастомные правила на
CEL). К концу модуля вы включаете restricted на namespace, читаете отказ
admission и пишете свою политику без установки внешних движков.

> Всё в этом модуле — **встроено в Kubernetes** (PSA GA с 1.25, VAP GA с 1.30),
> доп. установки не требуется. Kyverno/OPA — только для сложных кейсов (обзор в
> Части 3).

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl delete ns lab-restricted --ignore-not-found 2>/dev/null
kubectl version -o json 2>/dev/null | grep -i gitVersion | head -1   # нужен >=1.30 для VAP
```

## Стартовая проверка

Убедитесь, что кластер доступен:
```bash
kubectl get nodes
```

---

## Часть 1: Pod Security Admission (PSA)

### Теория для изучения перед частью

- **Pod Security Standards** — три профиля: `privileged` (без ограничений),
  `baseline` (запрет явно опасного), `restricted` (жёстко: non-root, drop caps,
  seccomp, no privilege escalation).
- **PSA** применяет профиль на уровне **namespace** через labels:
  `pod-security.kubernetes.io/enforce|warn|audit: <profile>`. `enforce`
  блокирует, `warn` предупреждает пользователя, `audit` пишет в audit-log.
- Проверка идёт на **admission** (до записи в etcd) — нарушающий под просто не
  создаётся.

**Профили по полям (что именно проверяется):**

| Контроль | privileged | baseline | restricted |
|----------|:---------:|:--------:|:----------:|
| privileged-контейнер | ✓ можно | ✗ | ✗ |
| hostNetwork / hostPID / hostIPC | ✓ | ✗ | ✗ |
| hostPath-тома | ✓ | ✗ | ✗ |
| `runAsNonRoot: true` | — | — (можно root) | **обязателен** |
| `allowPrivilegeEscalation: false` | — | — | **обязателен** |
| `capabilities: drop [ALL]` | — | ограничены | **обязателен** (add только `NET_BIND_SERVICE`) |
| `seccompProfile` RuntimeDefault/Localhost | — | — | **обязателен** |

**Включение профиля на namespace (YAML — это и есть `restricted-ns.yaml`):**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab-restricted
  labels:
    pod-security.kubernetes.io/enforce: restricted        # БЛОКИРУЕТ нарушителей
    pod-security.kubernetes.io/warn: restricted           # предупреждает в kubectl
    pod-security.kubernetes.io/audit: restricted          # пишет в audit-log
    # pod-security.kubernetes.io/enforce-version: v1.30    # (опц.) пиннуть версию правил
```

> **Стратегия миграции** на боевом namespace: сначала `warn`+`audit` (видно
> нарушителей, но ничего не ломается) → починить поды → только потом `enforce`.
> Так restricted не уронит существующие workload'ы внезапно.

#### PSA vs PSP — почему PSP убрали и что взамен

До k8s 1.21 ту же задачу решал **PodSecurityPolicy (PSP)** — admission-плагин с
объектами-политиками. PSP **deprecated в 1.21** и **удалён в 1.25**. В старых
кластерах вы его ещё встретите, поэтому важно понимать разницу:

| | PodSecurityPolicy (PSP, удалён в 1.25) | Pod Security Admission (PSA, с 1.25) |
|---|---|---|
| Гранулярность | отдельный объект-политика | 3 фиксированных профиля (priv/baseline/restricted) |
| Привязка | через RBAC (кто может использовать какой PSP) | label на namespace |
| Боль | какой PSP применится — зависело от RBAC и сортировки, **непредсказуемо** при нескольких подходящих | детерминированно: профиль namespace |
| Мутация | мог МУТИРОВать под (доставлять securityContext) | **только валидирует**, не меняет |
| Гибкость | произвольные правила | фиксированные профили (тонкая настройка — через VAP/Kyverno) |

- **Почему отказались:** PSP было трудно включить безопасно — при нескольких
  подходящих политиках выбор зависел от имён и RBAC, легко было «случайно» дать
  привилегии. И PSP мутировал поды, что усложняло отладку.
- **Путь миграции PSP → PSA:** замапить свои PSP на ближайший из трёх профилей;
  то, что не покрывается профилем (специфические правила), вынести в
  **ValidatingAdmissionPolicy** (Часть 2) или Kyverno/Gatekeeper (Часть 3).
- PSA НЕ мутирует — если поду нужны дефолтные `securityContext`, их ставит
  отдельный mutating-механизм (LimitRange/webhook), а PSA уже проверяет результат
  (см. порядок admission в Части 4).

---

**Цель:** включить restricted и увидеть, что проходит, а что отклоняется.

**Ресурсы:** `manifests/restricted-ns.yaml`, `good-pod.yaml`,
`broken/scenario-01/bad-pod.yaml`.

---

### 1.1 restricted: good проходит, bad отклоняется

```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl get ns lab-restricted -o jsonpath='{.metadata.labels}{"\n"}'
# ...enforce:restricted, warn:restricted, audit:restricted

# Соответствующий под (non-root, drop ALL, seccomp) — ПРОХОДИТ
kubectl apply -f manifests/good-pod.yaml
kubectl -n lab-restricted get pod good-pod
# good-pod   1/1   Running

# Нарушающий под (root-образ без securityContext) — ОТКЛОНЁН admission'ом
kubectl apply -f broken/scenario-01/bad-pod.yaml
# Error from server (Forbidden): error when creating "bad-pod.yaml":
#   pods "bad-pod" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities,
#   runAsNonRoot != true, seccompProfile ...
```

> Под `bad-pod` даже не создаётся — PSA отклонил его на входе. Это сильнее, чем
> `securityContext` в самом поде (там под создаётся, и kubelet может его уронить);
> PSA не пускает несоответствие в принципе.

**Контрольные вопросы:**
1. Три профиля Pod Security Standards — чем отличаются?
2. Чем `enforce` отличается от `warn`/`audit`?
3. На каком этапе PSA отклоняет под и почему это лучше, чем падение в рантайме?

---

## Часть 2: ValidatingAdmissionPolicy (CEL)

### Теория для изучения перед частью

- **ValidatingAdmissionPolicy (VAP)** — встроенный механизм кастомных правил на
  языке **CEL**, без внешнего webhook-сервера. Состоит из `ValidatingAdmissionPolicy`
  (что проверять) + `...Binding` (где применять, с каким действием).
- `validationActions`: `Deny` (блок), `Warn`, `Audit`.
- Заменяет простые validating-webhooks: быстрее, надёжнее (нет внешнего сервиса),
  декларативно.

**Два объекта VAP (аннотированный `vap-no-latest.yaml`):**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy            # ЧТО проверять (правило, переиспользуемо)
metadata: { name: no-latest-tag }
spec:
  matchConstraints:                        # к каким объектам вообще применимо
    resourceRules:
    - apiGroups: [""]; apiVersions: ["v1"]; operations: ["CREATE","UPDATE"]; resources: ["pods"]
  validations:
  - expression: "object.spec.containers.all(c, (c.image.matches('^.*:[a-zA-Z0-9_.-]+$') && !c.image.matches('^.*:latest$')) || c.image.matches('^.*@sha256:[a-f0-9]+$'))"
    message: "образы :latest или без тега запрещены"   # ^ CEL: проверка КАЖДОГО контейнера
---
kind: ValidatingAdmissionPolicyBinding     # ГДЕ применять + ЧТО делать (отделено от правила)
spec:
  policyName: no-latest-tag                 # ссылка на policy выше
  validationActions: ["Deny"]               # Deny | Warn | Audit
  matchResources:
    namespaceSelector:
      matchLabels: { kubernetes.io/metadata.name: lab }   # ТОЛЬКО ns lab
```

> **Зачем разделение policy/binding:** одну policy можно привязать к разным scope
> с разным действием — напр. `Warn` в dev-namespace и `Deny` в prod, не дублируя
> CEL. ⚠️ Binding cluster-scoped: `namespaceSelector` тут — единственная граница,
> поэтому такая VAP «утекает» на все ns, попавшие под селектор (грабли модуля 11).

**VAP vs внешний validating-webhook:**

| | ValidatingAdmissionPolicy | Validating Webhook |
|---|---|---|
| Язык | CEL (внутри apiserver) | любой (свой HTTP-сервер) |
| Инфраструктура | НЕТ (in-process) | под + Service + TLS-серт + caBundle |
| Латентность/риск | минимум, нет сетевого хопа | сетевой вызов; падение вебхука → отказ или дыра |
| Что умеет | только validate | validate + произвольная логика (внешние данные) |
| Доступность | GA c 1.30 | давно |

---

**Цель:** запретить образы `:latest` в namespace `lab`.

**Ресурс:** `manifests/vap-no-latest.yaml`.

---

### 2.1 Запрет :latest

```bash
kubectl apply -f manifests/vap-no-latest.yaml
kubectl get validatingadmissionpolicy no-latest-tag

# Под с :latest в lab — ОТКЛОНЁН политикой:
kubectl -n lab run bad --image=nginx:latest --restart=Never
# error: ... образы с тегом ':latest' или без тега запрещены — пиньте конкретную версию

# Под с конкретным тегом — проходит:
kubectl -n lab run good --image=nginx:1.27-alpine --restart=Never
kubectl -n lab delete pod good --ignore-not-found
```

> CEL-выражение `object.spec.containers.all(c, c.image.contains(':') &&
> (c.image.matches('^.*:[a-zA-Z0-9_.-]+$') && !c.image.matches('^.*:latest$')) || c.image.matches('^.*@sha256:[a-f0-9]+$'))` проверяет каждый контейнер. Так одной декларацией
> закрывается распространённый антипаттерн `:latest` (невоспроизводимые деплои).

**Контрольные вопросы:**
1. Из каких двух объектов состоит VAP и зачем разделение policy/binding?
2. Чем VAP лучше внешнего validating-webhook?
3. Какие `validationActions` бывают и когда `Warn` вместо `Deny`?

---

## Часть 3: Policy engines (Kyverno / OPA Gatekeeper) — обзор

### Теория для изучения перед частью

- Встроенных PSA + VAP хватает для запретов (validate). Когда нужно **мутировать**
  (доставить securityContext по умолчанию), **генерировать** (NetworkPolicy на
  каждый namespace) или **отчёты о соответствии** — берут policy-engine.
- **Kyverno** — политики как YAML (validate/mutate/generate), близок к k8s-стилю.
  **OPA Gatekeeper** — на языке Rego, мощнее, но круче порог входа. Оба ставятся
  через Helm и работают как admission-webhook.

| | **Kyverno** | **OPA Gatekeeper** |
|---|---|---|
| Язык политик | YAML (k8s-native) | Rego (DSL от OPA) |
| Действия | validate / **mutate** / **generate** / verifyImages | validate (mutate — новее/ограничен) |
| Порог входа | низкий (знакомый YAML) | выше (учить Rego) |
| Модель | ClusterPolicy/Policy + контроллер | ConstraintTemplate + Constraint |
| Когда брать | большинство k8s-native кейсов, нужны mutate/generate | сложная переиспользуемая логика, уже есть Rego/OPA |

> **Граница выбора:** PSA — стандартные профили; **VAP** — свой ЗАПРЕТ на CEL без
> инфраструктуры; **Kyverno/Gatekeeper** — когда нужно МУТИРОВАТЬ (доставить
> securityContext по умолчанию), ГЕНЕРИРОВАТЬ (NetworkPolicy на каждый ns) или
> строить отчёты о соответствии. Не тащить тяжёлый engine ради простого запрета.

---

```bash
# Установка Kyverno (пример, требует нод и Helm):
# helm repo add kyverno https://kyverno.github.io/kyverno/
# helm install kyverno kyverno/kyverno -n kyverno --create-namespace
# затем применять ClusterPolicy (пример — в tasks/03-policy-engines.md)
```

**Контрольные вопросы:**
1. Когда встроенных PSA/VAP недостаточно и нужен Kyverno/Gatekeeper?
2. Чем Kyverno отличается от OPA Gatekeeper по языку политик?
3. Что такое mutate/generate-политики и зачем они?

---

## Часть 4: Troubleshooting

### Теория: порядок admission-конвейера (что за чем выполняется)

Запрос на запись объекта проходит admission-плагины в **строго определённом
порядке** ПОСЛЕ AuthN/AuthZ и ДО записи в etcd. Порядок объясняет, почему одни
проверки видят результат других:

```
AuthN ─► AuthZ ─► ┌─────────────── ADMISSION ───────────────┐ ─► persist в etcd
                  │ 1. MUTATING (мутация объекта):           │
                  │    встроенные мутаторы → Mutating Webhooks│  ← могут ДОБАВИТЬ поля
                  │           │                              │    (sidecar, securityContext,
                  │           ▼                              │     defaults, labels)
                  │ 2. SCHEMA validation (OpenAPI/структура) │  ← объект валиден по CRD/типу?
                  │           │                              │
                  │           ▼                              │
                  │ 3. VALIDATING (отказ без мутации, парал.):│
                  │    • PSA (Pod Security Admission)        │
                  │    • VAP (ValidatingAdmissionPolicy, CEL)│  ← видят УЖЕ мутированный
                  │    • Validating Webhooks (Kyverno/OPA)  │     объект
                  └──────────────────────────────────────────┘
   Любой шаг 1–3 может отклонить ⇒ запрос падает целиком, в etcd ничего не пишется.
```

- **Сначала мутация, потом валидация.** Mutating-webhook может ДОБАВИТЬ
  `securityContext`/sidecar — и PSA/VAP проверяют уже изменённый под. Поэтому под,
  который «руками» нарушает restricted, может пройти, если мутатор его дочинил
  (и наоборот — мутатор может сломать соответствие).
- **Внутри валидации порядок между PSA/VAP/webhook не гарантирован**, но это
  неважно: любой отказ роняет запрос, мутаций на этом этапе уже нет.
- **Идемпотентность мутаторов важна:** при reinvocation (если поздний мутатор
  изменил объект) ранние mutating-webhook'и могут вызваться повторно.
- Практический вывод для дебага: «странное» содержимое отклонённого пода смотри
  ПОСЛЕ мутаторов (`kubectl ... --dry-run=server -o yaml` показывает объект уже
  промутированным) — именно его видели PSA/VAP.

### Теория: как читать отказ admission (кто именно отклонил)

Все отказы приходят как `Error from server (Forbidden)`, но ИСТОЧНИК виден по
формулировке — по ней сразу понятно, где чинить:

```
Error from server (Forbidden): pods "X" is forbidden:
   │
   ├─ violates PodSecurity "restricted:<v>": <список нарушений>
   │      └─> PSA. Список = ровно те поля securityContext, что чинить (см. good-pod).
   │
   ├─ ValidatingAdmissionPolicy '<name>' with binding '<b>' denied request: <message>
   │      └─> VAP. <message> = .spec.validations[].message; правило в самой policy.
   │
   └─ admission webhook "<name>" denied the request: <...>
          └─> ВНЕШНИЙ webhook (Kyverno/Gatekeeper/свой). Смотри политику в его движке.
```

| Источник | Маркер в ошибке | Где смотреть правило | Как ослабить |
|----------|-----------------|----------------------|--------------|
| PSA | `violates PodSecurity` | label ns `enforce` | привести securityContext / снизить профиль |
| VAP | `ValidatingAdmissionPolicy '…' denied` | `kubectl get validatingadmissionpolicy <n> -o yaml` | уточнить CEL / `Warn` / сузить binding |
| Webhook | `admission webhook "…" denied` | `kubectl get validatingwebhookconfiguration` | политику в Kyverno/Gatekeeper |

---

### Инцидент 1: под отклонён PSA (restricted)

Разобран в `broken/scenario-01/`. Симптом: `apply` падает с
`violates PodSecurity "restricted"`. Диагностика — прочитать, КАКИЕ требования
нарушены (в тексте ошибки перечислены), привести `securityContext` в
соответствие (см. `good-pod.yaml`). Профилактика: собирать под restricted с
самого начала; включать `warn` на namespace, чтобы видеть нарушения заранее.

### Инцидент 2: легитимный под не создаётся из-за VAP

```bash
# Если VAP слишком строга и режет нужное — посмотреть, какая политика сработала:
kubectl -n lab run x --image=nginx:latest --restart=Never 2>&1 | tail -1
# (сообщение из .spec.validations[].message). Лечение: уточнить CEL-выражение
# или сузить binding (matchResources), либо validationActions: Warn вместо Deny.
```

### Инцидент 3: PSA «не срабатывает»

```bash
# Частая причина — опечатка в label или профиль privileged. Проверить:
kubectl get ns lab-restricted -o jsonpath='{.metadata.labels}{"\n"}'
# должно быть pod-security.kubernetes.io/enforce: restricted (точное имя ключа!)
```

**Контрольные вопросы:**
1. Как прочитать из ошибки PSA, ЧТО именно нарушено?
2. Под отклонён VAP — где взять причину и как ослабить политику?
3. PSA «молчит» — две частые причины?

---

## Проверка модуля

```bash
kubectl apply -f manifests/restricted-ns.yaml
kubectl apply -f manifests/good-pod.yaml
kubectl apply -f manifests/vap-no-latest.yaml

bash verify/verify.sh
# [OK] PSA restricted enforced + good-pod Running + VAP no-latest present
# [OK] module 14 verified
```

`verify.sh`: namespace `lab-restricted` существует и `enforce=restricted` →
`good-pod` (соответствующий) Running → `ValidatingAdmissionPolicy/no-latest-tag`
установлена.

---

## Финальная карта ресурсов модуля

| Ресурс | Механизм | Что демонстрирует |
|--------|----------|-------------------|
| `lab-restricted` (ns) | Pod Security Admission | enforce restricted на namespace |
| `good-pod` | — | под, соответствующий restricted (проходит) |
| `bad-pod` (broken) | — | нарушение restricted → отклонён admission |
| `no-latest-tag` | ValidatingAdmissionPolicy (CEL) | запрет `:latest` без внешних движков |

---

## Теоретические вопросы (итоговые)

1. Опишите три профиля Pod Security Standards и три режима PSA.
2. Почему отклонение на admission лучше, чем падение пода в рантайме?
3. Чем `securityContext` в поде отличается от PSA на namespace?
4. Из чего состоит ValidatingAdmissionPolicy и чем она лучше webhook?
5. Когда встроенных средств мало и нужен Kyverno/Gatekeeper?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Включите `enforce=restricted` на ns и покажите, что `good-pod` проходит, а `bad-pod` отклонён; прочитайте список нарушений.
2. Напишите свою VAP на CEL (напр. запрет `hostNetwork`) + binding на ns `lab` и проверьте.
3. Различите по тексту ошибки источник отказа: PSA vs VAP vs (если есть) webhook.
4. Примените стратегию миграции `warn → audit → enforce` на «грязном» namespace.
5. ОБЯЗАТЕЛЬНО уберите cluster-scoped VAP после (он бьёт по ns `lab` в других модулях).

---

## Шпаргалка

```bash
# === Pod Security Admission ===
kubectl label ns <ns> pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label ns <ns> pod-security.kubernetes.io/warn=restricted --overwrite
kubectl get ns <ns> -o jsonpath='{.metadata.labels}'
# проверить «сухим прогоном», что пройдёт под профилем:
kubectl label --dry-run=server ns <ns> pod-security.kubernetes.io/enforce=restricted

# === ValidatingAdmissionPolicy ===
kubectl get validatingadmissionpolicy
kubectl get validatingadmissionpolicybinding
kubectl describe validatingadmissionpolicy no-latest-tag

# === Уборка ===
kubectl delete -f manifests/vap-no-latest.yaml
kubectl delete ns lab-restricted --ignore-not-found
```

---

## Уборка

```bash
kubectl delete -f manifests/vap-no-latest.yaml --ignore-not-found
kubectl delete ns lab-restricted --ignore-not-found
```
