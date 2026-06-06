# Лабораторная работа 22: Ingress и TLS (маршрутизация L7 + HTTPS + cert-manager)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Маршрутизация L7 (host и path)](#-1--l7-host--path)
  - [Теория для изучения перед частью](#----)
  - [1.1 Бэкенды и Ingress](#11---ingress)
  - [1.2 Проверка маршрутизации](#12--)
- [Часть 2: TLS termination (вручную)](#-2-tls-termination-)
  - [Теория для изучения перед частью](#----)
  - [2.1 Сгенерировать сертификат и Secret](#21----secret)
  - [2.2 Ingress с TLS и проверка HTTPS](#22-ingress--tls---https)
- [Часть 3: cert-manager — автоматический выпуск сертификатов](#-3-cert-manager----)
  - [Теория для изучения перед частью](#----)
  - [3.1 ClusterIssuer + Ingress с аннотацией](#31-clusterissuer--ingress--)
  - [3.2 Проверка HTTPS](#32--https)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Инцидент 1: Ingress без ADDRESS — неверный `ingressClassName`](#-1-ingress--address---ingressclassname)
  - [Прочие частые причины](#--)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)

Цель: научиться публиковать сервисы наружу через `Ingress` с маршрутизацией по
host/path, терминировать TLS (HTTPS) на контроллере — сначала вручную через
`kubernetes.io/tls` Secret, затем автоматически через **cert-manager**. К концу
модуля вы понимаете цепочку `IngressClass → Ingress → Service → Pod`, делаете
HTTPS с собственным сертификатом и автоматизируете выпуск сертификатов.

> Это развитие модуля 04 (там был intro в Ingress) и продолжение «зрелости» стека.
> Опирается на установленный ingress-controller (см. модуль 04, Часть 3).

---

## Предварительные требования

```bash
# kubeconfig нашего кластера (Kubespray); на другом стенде — свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) ingress-controller класса nginx (ставится один раз):
kubectl get ingressclass nginx || bash ../../scripts/bootstrap/03-install-ingress.sh
# (наш baremetal/NodePort с --report-node-internal-ip-address — см. модуль 04)

# 2) cert-manager для Части 3 (ставится один раз):
kubectl get crd certificates.cert-manager.io >/dev/null 2>&1 \
  || bash ../../scripts/bootstrap/07-install-cert-manager.sh

# 3) Чистый namespace lab
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab delete deploy,svc,cm,ingress,secret,certificate --all --ignore-not-found 2>/dev/null
```

> **Как обращаться к Ingress без внешнего DNS.** Имена `*.lab.local` нигде не
> зарегистрированы. В примерах используем `curl --resolve <host>:<port>:<IP>` —
> это подставляет имя без DNS. Внутри кластера бьём по ClusterIP контроллера; для
> внешнего доступа нужен его NodePort + firewall (см. ниже). Запомним ClusterIP:
> ```bash
> CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
> ```

---

## Стартовая проверка

```bash
kubectl get ingressclass
# NAME    CONTROLLER             ...
# nginx   k8s.io/ingress-nginx        <- класс, на который ссылаются наши Ingress

kubectl -n ingress-nginx get svc ingress-nginx-controller
# TYPE=NodePort, PORT(S)=80:30407/TCP,443:30905/TCP   <- HTTP/HTTPS снаружи через NodePort
```

---

## Часть 1: Маршрутизация L7 (host и path)

### Теория для изучения перед частью

- **Ingress** — L7 (HTTP/HTTPS) роутер: по `host` и `path` направляет запросы на
  разные `Service`. Сам по себе объект бесполезен — его «исполняет»
  **ingress-controller** (у нас ingress-nginx).
- **`ingressClassName`** связывает Ingress с конкретным контроллером (по имени
  `IngressClass`). Контроллер обслуживает ТОЛЬКО свои Ingress — чужой/неверный
  класс игнорируется (Часть 4).
- **host-based** роутинг: разные доменные имена → разные бэкенды. **path-based**:
  на одном host разные пути → разные бэкенды.
- **`pathType`**: `Prefix` (префикс пути), `Exact` (точное совпадение),
  `ImplementationSpecific`. **rewrite**: бэкенд видит исходный путь; чтобы отдать
  ему `/`, нужна аннотация контроллера `nginx.ingress.kubernetes.io/rewrite-target`.

```
            ┌──────── ingress-nginx (класс nginx) ────────┐
HTTP/HTTPS  │  смотрит Host + Path, выбирает backend       │
 ──────────>│  a.lab.local/      -> Service web-a          │──> Pod web-a
            │  b.lab.local/      -> Service web-b          │──> Pod web-b
            │  paths.lab.local/a -> web-a, /b -> web-b     │
            │  (нет совпадения)  -> default backend (404)  │
            └──────────────────────────────────────────────┘
```

---

**Цель:** развернуть два бэкенда и развести трафик по host и по path.

**Ресурсы:** `manifests/apps.yaml` (web-a, web-b с разным контентом),
`manifests/ingress.yaml` (`web-routing` host-based + `web-paths` path+rewrite).

---

### 1.1 Бэкенды и Ingress

```bash
kubectl -n lab apply -f manifests/apps.yaml
kubectl -n lab apply -f manifests/ingress.yaml
kubectl -n lab rollout status deploy/web-a --timeout=120s
kubectl -n lab rollout status deploy/web-b --timeout=120s

kubectl -n lab get ingress
# NAME          CLASS   HOSTS                       ADDRESS     PORTS
# web-routing   nginx   a.lab.local,b.lab.local     10.10.0.4   80
# web-paths     nginx   paths.lab.local             10.10.0.4   80
#                                                   ^ internal-IP ноды контроллера
```

### 1.2 Проверка маршрутизации

```bash
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
kubectl -n lab run curl --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- sh -c "
  curl -s --resolve a.lab.local:80:$CIP     http://a.lab.local/        # hello from web-a
  curl -s --resolve b.lab.local:80:$CIP     http://b.lab.local/        # hello from web-b
  curl -s --resolve paths.lab.local:80:$CIP http://paths.lab.local/a   # hello from web-a (path /a)
  curl -s --resolve paths.lab.local:80:$CIP http://paths.lab.local/b   # hello from web-b (path /b)
  curl -s -o /dev/null -w '%{http_code}\n' --resolve x.lab.local:80:$CIP http://x.lab.local/  # 404
"
```

> ✅ **Прогнано на Kubespray:** host-роутинг `a→web-a`, `b→web-b`; path-роутинг с
> `rewrite-target:/` — `/a→web-a`, `/b→web-b` (без rewrite бэкенд-nginx искал бы
> файл `/a` и вернул 404); неизвестный host → 404 (default backend).

**Контрольные вопросы:**
1. Что делает `ingressClassName` и что будет с Ingress при неверном классе?
2. Чем host-based роутинг отличается от path-based?
3. Зачем `rewrite-target` при path-роутинге на файловый бэкенд?

---

## Часть 2: TLS termination (вручную)

### Теория для изучения перед частью

- **TLS termination на Ingress:** контроллер принимает HTTPS, РАСШИФРОВЫВАЕТ и
  проксирует в бэкенд по обычному HTTP. Сертификат лежит в Secret типа
  **`kubernetes.io/tls`** (ключи `tls.crt` + `tls.key`).
- **`spec.tls`** в Ingress: `secretName` (откуда взять cert) + `hosts` (для каких
  имён). Контроллер выбирает сертификат по **SNI** (имя из ClientHello).
- Для имени без публичного CA годится **self-signed** сертификат — браузер
  предупредит, но шифрование работает (для внутренних/учебных целей).

---

**Цель:** включить HTTPS на `secure.lab.local` со своим сертификатом.

**Ресурс:** `manifests/tls/ingress-tls.yaml` (Secret создаётся ниже openssl'ом).

---

### 2.1 Сгенерировать сертификат и Secret

```bash
# Self-signed cert на secure.lab.local (SAN обязателен — по нему проверяют имя)
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /tmp/s.key -out /tmp/s.crt \
  -subj "/CN=secure.lab.local" -addext "subjectAltName=DNS:secure.lab.local"

# Secret типа kubernetes.io/tls из cert+key
kubectl -n lab create secret tls secure-tls --cert=/tmp/s.crt --key=/tmp/s.key
kubectl -n lab get secret secure-tls          # TYPE kubernetes.io/tls, DATA 2
```

### 2.2 Ingress с TLS и проверка HTTPS

```bash
kubectl -n lab apply -f manifests/tls/ingress-tls.yaml
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

kubectl -n lab run tls --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- sh -c "
  curl -sk --resolve secure.lab.local:443:$CIP https://secure.lab.local/    # hello from web-a
  curl -skv --resolve secure.lab.local:443:$CIP https://secure.lab.local/ 2>&1 | grep -i 'subject:\|issuer:'
"
# *  subject: CN=secure.lab.local
# *  issuer:  CN=secure.lab.local       <- контроллер отдаёт ИМЕННО наш сертификат
```

> ✅ **Прогнано:** контроллер терминирует TLS и предъявляет наш cert
> (`subject/issuer: CN=secure.lab.local`); `-k` нужен, т.к. self-signed (не доверен
> системно). Используем ОТДЕЛЬНЫЙ host `secure.lab.local` — если повесить TLS на
> уже занятый `a.lab.local/`, ingress-nginx отклонит дубль host+path на admission.

**Контрольные вопросы:**
1. Где хранится сертификат для Ingress и какого типа этот Secret?
2. Что значит «TLS termination на контроллере» и по HTTP или HTTPS он идёт к бэкенду?
3. Как контроллер выбирает, какой сертификат отдать, если хостов несколько (SNI)?

---

## Часть 3: cert-manager — автоматический выпуск сертификатов

### Теория для изучения перед частью

- **cert-manager** — оператор (CRD + контроллер), который выпускает и продлевает
  TLS-сертификаты. Ключевые CRD: **`Issuer`/`ClusterIssuer`** (КТО выдаёт —
  SelfSigned / CA / ACME-Let's Encrypt), **`Certificate`** (ЧТО выпустить → кладёт
  результат в Secret).
- **ingress-shim:** при аннотации на Ingress `cert-manager.io/cluster-issuer: <name>`
  cert-manager САМ создаёт `Certificate` из `spec.tls` и кладёт cert в `secretName`
  — без ручного openssl. Это production-паттерн (особенно с ACME — автопродление).
- **SelfSigned ClusterIssuer** подписывает каждый сертификат сам собой — работает
  офлайн (без внешнего CA/DNS), удобно для внутренних демо. В проде — ACME/CA.

---

**Цель:** выпустить сертификат для `auto.lab.local` автоматически.

**Ресурсы:** `manifests/cert-manager/{clusterissuer,ingress-cm}.yaml`.

---

### 3.1 ClusterIssuer + Ingress с аннотацией

```bash
kubectl apply -f manifests/cert-manager/clusterissuer.yaml      # ClusterIssuer/selfsigned-issuer
kubectl -n lab apply -f manifests/cert-manager/ingress-cm.yaml  # Ingress auto-tls + аннотация

# cert-manager САМ создаёт Certificate и Secret auto-tls (через несколько секунд):
kubectl -n lab get certificate,secret auto-tls
# certificate.cert-manager.io/auto-tls   READY=True
# secret/auto-tls                        TYPE kubernetes.io/tls   <- создан АВТОМАТИЧЕСКИ
```

### 3.2 Проверка HTTPS

```bash
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
kubectl -n lab run cm --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- \
  curl -sk --resolve auto.lab.local:443:$CIP https://auto.lab.local/      # hello from web-b
```

> ✅ **Прогнано:** аннотация `cert-manager.io/cluster-issuer` → ingress-shim создал
> `Certificate/auto-tls` (Ready) → cert-manager выпустил cert в `Secret/auto-tls`
> САМ → HTTPS работает. Сертификаты cert-manager кладут имя в **SAN**
> (`DNS:auto.lab.local`), а `CN` оставляют пустым (CN устарел). Ручной шаг openssl
> из Части 2 больше не нужен — и cert будет автопродлеваться.

**Контрольные вопросы:**
1. За что отвечают `ClusterIssuer` и `Certificate` в cert-manager?
2. Что делает ingress-shim при аннотации `cert-manager.io/cluster-issuer`?
3. Чем SelfSigned-issuer отличается от ACME (Let's Encrypt) и когда какой брать?

---

## Часть 4: Troubleshooting

### Инцидент 1: Ingress без ADDRESS — неверный `ingressClassName`

Оформлен в `broken/scenario-01/`. `ingressClassName: nginx-does-not-exist` —
контроллер игнорирует такой Ingress.

```bash
kubectl -n lab apply -f broken/scenario-01/ingress.yaml
kubectl -n lab get ingress broken-routing
# ADDRESS пуст   <- контроллер не взял Ingress (класса nginx-does-not-exist нет)
kubectl get ingressclass                                      # реально есть только nginx
kubectl -n lab apply -f solutions/01-wrong-class/ingress.yaml # class -> nginx
# через ~10с ADDRESS=10.10.0.4 — контроллер принял
```

### Прочие частые причины

| Симптом | Причина | Где смотреть / фикс |
|---------|---------|---------------------|
| ADDRESS пуст | нет контроллера / неверный класс | `kubectl get ingressclass`; класс = nginx |
| `404 default backend` | host/path не совпал ни с одним Ingress | проверить `host`/`pathType`; SNI = host |
| HTTPS отдаёт «не тот» cert | SNI не совпал / нет `spec.tls` для host | cert по SNI; добавить host в `spec.tls.hosts` |
| `certificate verify failed` | self-signed не доверен | это норма для демо; `curl -k` / добавить CA в trust |
| admission `host ... already defined` | дубль host+path в двух Ingress | разнести по host/path |
| cert-manager Secret не появился | issuer не Ready / webhook не готов | `kubectl describe certificate <n>`, события cert-manager |

**Контрольные вопросы:**
1. Ingress без ADDRESS — с чего начать диагностику?
2. Почему один и тот же host+path в двух Ingress отвергается?
3. Как понять, какой сертификат реально отдал контроллер?

---

## Проверка модуля

```bash
kubectl -n lab apply -k manifests/                              # apps + routing-ingress
kubectl -n lab apply -f manifests/cert-manager/clusterissuer.yaml -f manifests/cert-manager/ingress-cm.yaml
kubectl -n lab rollout status deploy/web-a --timeout=120s
kubectl -n lab rollout status deploy/web-b --timeout=120s

bash verify/verify.sh
# [OK] ingress-nginx controller ready + web-routing(class=nginx)
# [OK] cert-manager: Certificate/auto-tls Ready + Secret/auto-tls создан автоматически
# [OK] module 22 verified
```

`verify.sh`: namespace `lab` → `web-a`/`web-b` готовы → `Ingress/web-routing` с
`ingressClassName=nginx` → контроллер `ingress-nginx` готов → (мягко) cert-manager
`Certificate/auto-tls` Ready + Secret создан. Без контроллера — `[FAIL]`; без
cert-manager — `[WARN]` (Части 1-2 от него не зависят).

---

## Финальная карта ресурсов модуля

| Ресурс | Часть | Что демонстрирует |
|--------|-------|-------------------|
| `web-a`/`web-b` (Deploy+Svc+CM) | 1 | бэкенды с разным контентом |
| `web-routing` (Ingress) | 1 | host-based роутинг (a/b.lab.local) |
| `web-paths` (Ingress + rewrite) | 1 | path-based роутинг (/a,/b) |
| `secure-tls` (Ingress) + `secure-tls` (Secret) | 2 | ручной TLS (openssl + kubernetes.io/tls) |
| `selfsigned-issuer` (ClusterIssuer) | 3 | cert-manager: КТО выдаёт |
| `auto-tls` (Ingress+Certificate+Secret) | 3 | автоматический выпуск через ingress-shim |
| `broken-routing` (broken→fix) | 4 | неверный ingressClassName |

---

## Теоретические вопросы (итоговые)

1. Опишите цепочку `IngressClass → Ingress → Service → Pod` и роль контроллера.
2. host-based vs path-based роутинг; зачем `rewrite-target`?
3. Что такое TLS termination на Ingress и в каком Secret лежит сертификат?
4. Как контроллер выбирает сертификат при нескольких host (SNI)?
5. Роли `ClusterIssuer`/`Certificate`/ingress-shim в cert-manager.
6. Чем SelfSigned-issuer отличается от ACME и когда какой нужен?

---

## Практические задания (отработка)

> Делайте на живом кластере; проверяйте себя командами и `verify/verify.sh`.

1. Разведите трафик по host (a/b.lab.local) и по path (с `rewrite-target`); проверьте curl'ом через контроллер.
2. Сгенерируйте self-signed cert (openssl) + Secret tls и включите HTTPS; убедитесь `curl -v`, что отдаётся ВАШ cert.
3. cert-manager: повесьте аннотацию `cluster-issuer` на Ingress и убедитесь, что Secret создаётся САМ.
4. Воспроизведите Ingress без ADDRESS (неверный `ingressClassName`) и почините.
5. Поймайте отказ admission «host ... already defined», повесив TLS на уже занятый host+path.

---

## Шпаргалка

```bash
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
kubectl get ingressclass
kubectl -n lab get ingress,certificate,secret
# routing (in-cluster, без DNS):
kubectl -n lab run c --image=curlimages/curl:8.10.1 --restart=Never -i --rm -- \
  curl -s --resolve a.lab.local:80:$CIP http://a.lab.local/
# HTTPS:
#   curl -sk --resolve secure.lab.local:443:$CIP https://secure.lab.local/
#   curl -skv ... 2>&1 | grep -i 'subject:\|issuer:'        # какой cert отдан
# TLS secret вручную:
#   openssl req -x509 -nodes -newkey rsa:2048 -keyout k -out c -subj /CN=h -addext subjectAltName=DNS:h
#   kubectl -n lab create secret tls <name> --cert=c --key=k
# cert-manager:
kubectl -n lab describe certificate auto-tls          # события выпуска
kubectl get clusterissuer

# === Уборка ===
kubectl -n lab delete -k manifests/
kubectl -n lab delete -f manifests/cert-manager/ingress-cm.yaml --ignore-not-found
kubectl -n lab delete ingress secure-tls --ignore-not-found
kubectl -n lab delete secret secure-tls auto-tls --ignore-not-found
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found
```

---


## Чему вы научились

В этом модуле вы научились:
- Установке Ingress-контроллера (NGINX)
- Автоматическому выпуску SSL-сертификатов через cert-manager
- Настройке HTTP(S) маршрутизации

## Уборка

```bash
kubectl -n lab delete -k manifests/
kubectl -n lab delete -f manifests/cert-manager/ingress-cm.yaml --ignore-not-found
kubectl -n lab delete ingress secure-tls --ignore-not-found
kubectl -n lab delete secret secure-tls auto-tls --ignore-not-found
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found
# ingress-nginx и cert-manager — общие аддоны, ОСТАВЛЯЕМ для других модулей.
```
