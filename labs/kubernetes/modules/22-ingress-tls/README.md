# Лабораторная работа 22: Ingress и TLS (маршрутизация L7 + HTTPS + cert-manager)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#предварительные-требования)
- [Стартовая проверка](#стартовая-проверка)
- [Часть 1: Маршрутизация L7 (host и path)](#часть-1-маршрутизация-l7-host-и-path)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-1)
  - [1.1 Бэкенды и Ingress](#11-бэкенды-и-ingress)
  - [1.2 Проверка маршрутизации](#12-проверка-маршрутизации)
- [Часть 2: TLS termination (вручную)](#часть-2-tls-termination-вручную)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-2)
  - [2.1 Сгенерировать сертификат и Secret](#21-сгенерировать-сертификат-и-secret)
  - [2.2 Ingress с TLS и проверка HTTPS](#22-ingress-с-tls-и-проверка-https)
- [Часть 3: cert-manager — автоматический выпуск сертификатов](#часть-3-cert-manager--автоматический-выпуск-сертификатов)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-3)
  - [3.1 ClusterIssuer + Ingress с аннотацией](#31-clusterissuer--ingress-с-аннотацией)
  - [3.2 Проверка HTTPS](#32-проверка-https)
- [Часть 4: Troubleshooting — боевые инциденты](#часть-4-troubleshooting--боевые-инциденты)
  - [Теория для изучения перед частью](#теория-для-изучения-перед-частью-4)
  - [Инцидент 1: Ingress не получает IP-адрес (ADDRESS пуст)](#инцидент-1-ingress-не-получает-ip-адрес-address-пуст)
  - [Инцидент 2: Ошибка 404 Not Found (default backend)](#инцидент-2-ошибка-404-not-found-default-backend)
  - [Инцидент 3: Ошибка SSL certificate problem: self-signed certificate](#инцидент-3-ошибка-ssl-certificate-problem-self-signed-certificate)
  - [Инцидент 4: Сертификат не выпускается (Certificate не переходит в Ready)](#инцидент-4-сертификат-не-выпускается-certificate-не-переходит-в-ready)
- [Проверка модуля](#проверка-модуля)
- [Финальная карта ресурсов модуля](#финальная-карта-ресурсов-модуля)
- [Теоретические вопросы (итоговые)](#теоретические-вопросы-итоговые)
  - [Блок 1: Ingress и маршрутизация](#блок-1-ingress-и-маршрутизация)
  - [Блок 2: TLS и сертификаты](#блок-2-tls-и-сертификаты)
  - [Блок 3: cert-manager](#блок-3-cert-manager)
  - [Блок 4: Troubleshooting](#блок-4-troubleshooting)
- [Практические задания (отработка)](#практические-задания-отработка)
- [Шпаргалка](#шпаргалка)
- [Чему вы научились](#чему-вы-научились)
- [Уборка](#уборка)
<!-- /TOC -->

> ⏱ время ~45 мин · сложность 4/5 · пререквизиты: Трек 1 (Core)

---

Цель всей работы: научиться осознанно публиковать веб-приложения и сервисы наружу через `Ingress`, используя продвинутую маршрутизацию по `host` и `path`. Вы поймете, как работает терминирование TLS (HTTPS) на контроллере. Сначала мы вручную сгенерируем и добавим сертификаты через Secret типа `kubernetes.io/tls`, а затем полностью автоматизируем этот процесс с помощью мощного инструмента **cert-manager**. К концу модуля вы будете чётко понимать полную цепочку прохождения трафика `IngressClass → Ingress → Service → Pod` и уметь диагностировать типовые проблемы маршрутизации и сертификатов.

> Это логическое продолжение и глубокое развитие темы из модуля 04 (где было лишь базовое введение в Ingress), демонстрирующее "зрелость" стека Kubernetes. Работа опирается на установленный ingress-controller (см. модуль 04, Часть 3). Все манифесты находятся в директории `manifests/`, поломки в `broken/`, решения в `solutions/`.

---

## Предварительные требования

Для успешного выполнения лабораторной работы вам потребуется настроенное окружение и установленные базовые компоненты.

```bash
# Укажем kubeconfig нашего кластера (для Kubespray); на другом стенде используйте свой путь/контекст
export KUBECONFIG=/root/.kube/kubespray.conf

# 1) Проверка работоспособности кластера
kubectl cluster-info
kubectl version --short

# 2) Проверка наличия ingress-controller класса nginx (ставится один раз на кластер):
kubectl get ingressclass nginx || bash ../../scripts/bootstrap/03-install-ingress.sh
# (наш контроллер использует baremetal/NodePort с --report-node-internal-ip-address — см. модуль 04)

# 3) Установка cert-manager для Части 3 (ставится один раз на кластер):
# Проверяем наличие CRD cert-manager, если их нет - запускаем скрипт установки
kubectl get crd certificates.cert-manager.io >/dev/null 2>&1 \
  || bash ../../scripts/bootstrap/07-install-cert-manager.sh

# Убедимся, что поды cert-manager запущены и находятся в статусе Running
kubectl -n cert-manager get pods

# 4) Создание чистого namespace lab для изоляции ресурсов нашей лабораторной работы
kubectl create ns lab --dry-run=client -o yaml | kubectl apply -f -

# Очистка namespace lab от предыдущих экспериментов (если они были)
kubectl -n lab delete deploy,svc,cm,ingress,secret,certificate --all --ignore-not-found 2>/dev/null

# Удобный алиас для работы в рамках данного namespace
alias k='kubectl -n lab'
```

> **Как обращаться к Ingress без внешнего DNS?**
> Имена вида `*.lab.local` нигде публично не зарегистрированы. Для тестирования локальных или учебных доменов мы будем использовать мощную возможность утилиты curl — флаг `--resolve <host>:<port>:<IP>`. Это позволяет подставить нужный IP-адрес для имени домена в обход системного DNS. 
> 
> Внутри кластера мы можем обращаться по ClusterIP контроллера. Для внешнего доступа нужен был бы его NodePort или LoadBalancer. В наших примерах мы найдем внутренний IP контроллера:
> ```bash
> CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
> echo "IP Ingress контроллера: $CIP"
> ```

---

## Стартовая проверка

Прежде чем приступать к созданию Ingress ресурсов, необходимо убедиться, что контроллер готов их обрабатывать.

```bash
# Посмотрим доступные IngressClass в кластере
kubectl get ingressclass
```

Ожидаемый вывод:
```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       2d
```
*Здесь `nginx` — это класс, на который будут ссылаться наши Ingress объекты через `ingressClassName`.*

```bash
# Проверим сервис самого контроллера
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

Ожидаемый вывод:
```
NAME                       TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller   NodePort   10.233.56.120   <none>        80:30407/TCP,443:30905/TCP   2d
```
*Обратите внимание на `TYPE=NodePort`. Это означает, что HTTP/HTTPS доступен снаружи через NodePort (в данном примере 30407 и 30905 соответственно).*

---

## Часть 1: Маршрутизация L7 (host и path)

### Теория для изучения перед частью

- **Ingress** — это L7 (HTTP/HTTPS) роутер в Kubernetes. В отличие от Service (L4), он понимает структуру HTTP-запросов. Он может по `host` (доменному имени) и `path` (пути в URL) направлять запросы на разные `Service`. Важно понимать: сам по себе объект Ingress — это просто правило (конфигурация). Его «исполняет» реальное приложение — **ingress-controller** (в нашем случае это NGINX).
- **`ingressClassName`** — критически важное поле. Оно связывает ваш Ingress с конкретным контроллером (по его имени `IngressClass`). Контроллер читает ТОЛЬКО те Ingress ресурсы, которые явно указывают его класс. Ingress с чужим или неверным классом будет проигнорирован (это мы увидим в Части 4).
- **Host-based роутинг**: позволяет на одном IP-адресе обслуживать множество доменов. Разные доменные имена (`a.lab.local`, `b.lab.local`) → разные бэкенды.
- **Path-based роутинг**: на одном домене можно разделить логику по путям. Например, `/api` идет на один микросервис, а `/` — на фронтенд.
- **`pathType`**: 
  - `Prefix`: совпадение по префиксу пути (например, `/a` совпадет с `/a/b/c`).
  - `Exact`: строгое точное совпадение.
  - `ImplementationSpecific`: поведение зависит от конкретного контроллера.
- **Аннотация `rewrite-target`**: когда Ingress перенаправляет запрос `/a` на бэкенд, по умолчанию бэкенд видит запрос именно к `/a`. Если ваш бэкенд (например, веб-сервер) ожидает корень `/`, он вернет 404. Чтобы "отрезать" `/a` и передать бэкенду `/`, используется специфичная для NGINX аннотация `nginx.ingress.kubernetes.io/rewrite-target`.

```text
            ┌──────── ingress-nginx (класс nginx) ────────┐
HTTP/HTTPS  │  смотрит Host + Path, выбирает backend       │
 ──────────>│  a.lab.local/      -> Service web-a          │──> Pod web-a
            │  b.lab.local/      -> Service web-b          │──> Pod web-b
            │  paths.lab.local/a -> web-a, /b -> web-b     │
            │  (нет совпадения)  -> default backend (404)  │
            └──────────────────────────────────────────────┘
```

---

**Цель:** Развернуть два независимых веб-бэкенда и развести между ними трафик: сначала по доменным именам (host), а затем по путям (path).

**Ресурсы:** `manifests/apps.yaml` (содержит Deployment и Service для web-a и web-b с разным контентом), `manifests/ingress.yaml` (правила Ingress: `web-routing` для host-based и `web-paths` для path-based с rewrite).

---

### 1.1 Бэкенды и Ingress

Для начала развернем приложения, которые будут отвечать на наши запросы.

```bash
# Применяем манифесты приложений (Deployment + Service)
kubectl -n lab apply -f manifests/apps.yaml

# Применяем правила Ingress
kubectl -n lab apply -f manifests/ingress.yaml

# Дожидаемся готовности подов (статус Running)
kubectl -n lab rollout status deploy/web-a --timeout=120s
kubectl -n lab rollout status deploy/web-b --timeout=120s
```

Теперь проверим созданные Ingress ресурсы:

```bash
kubectl -n lab get ingress
```

Ожидаемый вывод:
```
NAME          CLASS   HOSTS                       ADDRESS     PORTS   AGE
web-paths     nginx   paths.lab.local             10.10.0.4   80      1m
web-routing   nginx   a.lab.local,b.lab.local     10.10.0.4   80      1m
```
*Обратите внимание: поле `ADDRESS` содержит внутренний IP ноды контроллера. Если `ADDRESS` пуст долгое время, это верный признак проблем с Ingress (подробнее в Troubleshooting).*

### 1.2 Проверка маршрутизации

Воспользуемся curl для отправки запросов. Мы запустим curl внутри кластера, чтобы обратиться к ClusterIP Ingress контроллера.

```bash
# Получаем IP Ingress контроллера
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

# Запускаем под с curl для проверки
kubectl -n lab run curl --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- sh -c "
  echo '--- Host-based routing ---'
  curl -s --resolve a.lab.local:80:$CIP     http://a.lab.local/
  curl -s --resolve b.lab.local:80:$CIP     http://b.lab.local/
  
  echo '--- Path-based routing (with rewrite) ---'
  curl -s --resolve paths.lab.local:80:$CIP http://paths.lab.local/a
  curl -s --resolve paths.lab.local:80:$CIP http://paths.lab.local/b
  
  echo '--- Unknown host (404 expected) ---'
  curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' --resolve x.lab.local:80:$CIP http://x.lab.local/
"
```

Ожидаемый результат:
```text
--- Host-based routing ---
hello from web-a
hello from web-b
--- Path-based routing (with rewrite) ---
hello from web-a
hello from web-b
--- Unknown host (404 expected) ---
HTTP Status: 404
```

> ✅ **Проверено и работает:** 
> - Host-роутинг: `a.lab.local` направлен на `web-a`, `b.lab.local` — на `web-b`.
> - Path-роутинг с `rewrite-target:/`: `/a` перенаправлен на `web-a`, а `/b` — на `web-b`. Важно понимать: без rewrite NGINX бэкенда (внутри пода) искал бы файл `/a` в своей директории и вернул бы ошибку 404.
> - Неизвестный host: Запрос к `x.lab.local` возвращает 404 от default backend Ingress контроллера.

**Контрольные вопросы для самопроверки (Часть 1):**
1. Какую роль играет поле `ingressClassName` и что произойдет с Ingress, если указать неверный класс?
2. В чем принципиальное отличие host-based роутинга от path-based роутинга? В каких сценариях лучше использовать каждый из них?
3. Зачем именно нужна аннотация `rewrite-target` при path-роутинге на статический файловый бэкенд? Что бы произошло без нее?

---

## Часть 2: TLS termination (вручную)

### Теория для изучения перед частью

- **TLS termination (Терминирование TLS) на Ingress:** Это процесс, при котором Ingress-контроллер принимает зашифрованный HTTPS-трафик, РАСШИФРОВЫВАЕТ его с использованием своих сертификатов и далее проксирует трафик в бэкенд (в поды) по обычному, не зашифрованному HTTP. Это снимает вычислительную нагрузку по расшифровке с бэкендов и централизует управление сертификатами.
- **Хранение сертификатов:** Сертификат и закрытый ключ лежат в объекте Secret со специальным типом **`kubernetes.io/tls`**. Этот Secret содержит ключи `tls.crt` (сертификат) и `tls.key` (приватный ключ).
- **Настройка в Ingress:** В секции **`spec.tls`** ресурса Ingress указывается `secretName` (откуда брать сертификат) и `hosts` (для каких доменных имен он валиден).
- **SNI (Server Name Indication):** Ingress-контроллер обслуживает множество доменов на одном IP-адресе. Как он понимает, какой сертификат отдать клиенту на этапе рукопожатия TLS? Он использует расширение SNI протокола TLS: клиент в пакете ClientHello передает желаемое имя хоста, и контроллер выбирает соответствующий сертификат.
- **Самоподписанные сертификаты (Self-signed):** Для локальных доменов без публичного CA вполне подходит self-signed сертификат. Да, браузер выдаст предупреждение безопасности (так как сертификат не подписан доверенным удостоверяющим центром), но само шифрование трафика будет работать безупречно. Это идеально для внутренних или учебных целей.

---

**Цель:** Включить поддержку HTTPS на домене `secure.lab.local`, сгенерировав собственный самоподписанный сертификат вручную.

**Ресурс:** `manifests/tls/ingress-tls.yaml` (Secret мы создадим сами с помощью утилиты `openssl`).

---

### 2.1 Сгенерировать сертификат и Secret

Создадим самоподписанный сертификат с помощью OpenSSL. Важно указать Subject Alternative Name (SAN), так как современные клиенты (включая curl и браузеры) проверяют именно его, а не устаревшее поле Common Name (CN).

```bash
# Генерируем Self-signed сертификат на secure.lab.local сроком на 1 год (365 дней)
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /tmp/s.key -out /tmp/s.crt \
  -subj "/CN=secure.lab.local" -addext "subjectAltName=DNS:secure.lab.local"
```

Теперь создадим Kubernetes Secret из сгенерированных файлов:

```bash
# Создаем Secret типа kubernetes.io/tls
kubectl -n lab create secret tls secure-tls --cert=/tmp/s.crt --key=/tmp/s.key

# Проверяем, что Secret создан корректно
kubectl -n lab get secret secure-tls
```

Ожидаемый вывод:
```
NAME         TYPE                DATA   AGE
secure-tls   kubernetes.io/tls   2      15s
```
*В `DATA` находится 2 элемента: `tls.crt` и `tls.key`.*

### 2.2 Ingress с TLS и проверка HTTPS

Применяем манифест Ingress, который ссылается на созданный Secret.

```bash
kubectl -n lab apply -f manifests/tls/ingress-tls.yaml
```

Давайте посмотрим на `manifests/tls/ingress-tls.yaml` изнутри:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-tls
  namespace: lab
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.lab.local
    secretName: secure-tls   # Ссылка на наш Secret
  rules:
  - host: secure.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-a
            port:
              number: 80
```

Проверим доступность по HTTPS:

```bash
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

# Запускаем под с curl для проверки HTTPS
kubectl -n lab run tls --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- sh -c "
  echo '--- Запрос по HTTPS ---'
  curl -sk --resolve secure.lab.local:443:$CIP https://secure.lab.local/
  
  echo -e '\n--- Проверка деталей сертификата ---'
  curl -skv --resolve secure.lab.local:443:$CIP https://secure.lab.local/ 2>&1 | grep -i 'subject:\|issuer:'
"
```

Ожидаемый результат:
```text
--- Запрос по HTTPS ---
hello from web-a

--- Проверка деталей сертификата ---
*  subject: CN=secure.lab.local
*  issuer: CN=secure.lab.local
```

> ✅ **Проверено и работает:** 
> Контроллер успешно терминирует TLS и предъявляет наш сертификат (`subject/issuer: CN=secure.lab.local`). 
> Обратите внимание: флаг `-k` (`--insecure`) обязателен для curl, так как сертификат самоподписанный и системно ему нет доверия. 
> Мы использовали отдельный хост `secure.lab.local`. Если бы мы попытались повесить TLS на уже существующий `a.lab.local/` с другим Ingress, ingress-nginx мог бы отклонить это как конфликт конфигурации (duplicate path).

**Контрольные вопросы для самопроверки (Часть 2):**
1. В объекте какого типа и с какими ключами хранится TLS сертификат для Ingress?
2. Что означает фраза «TLS termination на контроллере»? По какому протоколу (HTTP или HTTPS) трафик идет от контроллера к подам бэкенда?
3. Каким образом Ingress-контроллер понимает, какой из множества сертификатов отдать клиенту (что такое SNI)?

---

## Часть 3: cert-manager — автоматический выпуск сертификатов

### Теория для изучения перед частью

- Управление сертификатами вручную (генерация openssl, создание секретов, отслеживание сроков действия и ротация) — это утомительно и подвержено ошибкам.
- **cert-manager** — это популярный Kubernetes оператор (состоящий из CRD и контроллеров), который полностью автоматизирует процесс выпуска и регулярного продления TLS-сертификатов.
- **Ключевые CRD (Custom Resource Definitions) в cert-manager:**
  - **`Issuer` / `ClusterIssuer`**: Представляют собой центры сертификации (CA). Они отвечают на вопрос **КТО** выдаёт сертификат. Могут быть разных типов: `SelfSigned` (как в нашем примере), `CA` (корпоративный удостоверяющий центр), `ACME` (Let's Encrypt для публичных доменов). `ClusterIssuer` действует на уровне всего кластера, а `Issuer` — только в пределах одного namespace.
  - **`Certificate`**: Отвечает на вопрос **ЧТО** нужно выпустить. В этом ресурсе описывается домен, срок действия и имя Secret'а, в который нужно положить готовый сертификат.
- **ingress-shim:** Это компонент cert-manager, который невероятно упрощает жизнь. При наличии специальной аннотации на ресурсе Ingress (например, `cert-manager.io/cluster-issuer: <name>`), cert-manager **АВТОМАТИЧЕСКИ** замечает это, сам создает ресурс `Certificate` на основе блока `spec.tls` из Ingress, выпускает сертификат и кладет его в указанный `secretName`. Никаких ручных команд `openssl` больше не нужно!
- В production-средах связка `cert-manager` + `Let's Encrypt` (через ACME) является де-факто стандартом для получения бесплатных автопродляемых SSL-сертификатов. Для локальных сред мы используем `SelfSigned ClusterIssuer`.

---

**Цель:** Автоматически выпустить сертификат для нового домена `auto.lab.local` без единой команды `openssl`.

**Ресурсы:** `manifests/cert-manager/clusterissuer.yaml` (определение того, КТО выдает), `manifests/cert-manager/ingress-cm.yaml` (наш Ingress с аннотацией-триггером).

---

### 3.1 ClusterIssuer + Ingress с аннотацией

Сначала создадим ClusterIssuer типа SelfSigned.

```bash
# Создаем ClusterIssuer на уровне кластера
kubectl apply -f manifests/cert-manager/clusterissuer.yaml
```

Посмотрим его содержимое:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

Теперь применим Ingress ресурс с аннотацией.
```bash
# Создаем Ingress для auto.lab.local с аннотацией cert-manager
kubectl -n lab apply -f manifests/cert-manager/ingress-cm.yaml
```

Давайте посмотрим на `manifests/cert-manager/ingress-cm.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auto-tls
  namespace: lab
  annotations:
    # Эта аннотация - магия! Она говорит cert-manager-у: "Выпусти мне сертификат, используя этот ClusterIssuer"
    cert-manager.io/cluster-issuer: "selfsigned-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - auto.lab.local
    secretName: auto-tls  # Secret будет создан АВТОМАТИЧЕСКИ!
  rules:
  - host: auto.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-b
            port:
              number: 80
```

Проверим магию в действии. `cert-manager` должен был создать `Certificate` и `Secret`.

```bash
# Дадим пару секунд на выпуск сертификата
sleep 3
kubectl -n lab get certificate,secret auto-tls
```

Ожидаемый вывод:
```
NAME                                       READY   SECRET     AGE
certificate.cert-manager.io/auto-tls       True    auto-tls   10s

NAME               TYPE                DATA   AGE
secret/auto-tls    kubernetes.io/tls   3      10s
```
*Успех! `READY=True` означает, что сертификат успешно выпущен. Секрет `auto-tls` был создан без нашего вмешательства.*

### 3.2 Проверка HTTPS

```bash
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

# Проверяем работу HTTPS
kubectl -n lab run cm --image=curlimages/curl:8.10.1 --restart=Never -i --rm --command -- \
  curl -sk --resolve auto.lab.local:443:$CIP https://auto.lab.local/
```

Ожидаемый результат:
```text
hello from web-b
```

> ✅ **Проверено и работает:** 
> Механизм ingress-shim отработал идеально. Аннотация `cert-manager.io/cluster-issuer` послужила триггером для создания ресурса `Certificate/auto-tls`. Затем cert-manager выпустил сертификат и сохранил его в `Secret/auto-tls`. HTTPS доступен.
> Важная деталь: сертификаты, выпущенные современными версиями cert-manager, помещают имя домена только в **SAN** (`DNS:auto.lab.local`), оставляя поле `CN` (Common Name) пустым, так как использование CN для доменов считается устаревшим (deprecated).
> Ручные манипуляции с openssl остались в прошлом. Более того, cert-manager будет автоматически продлевать этот сертификат до истечения его срока действия.

**Контрольные вопросы для самопроверки (Часть 3):**
1. В чем разница между `ClusterIssuer` и `Certificate` в архитектуре cert-manager?
2. Что именно делает механизм `ingress-shim` при обнаружении аннотации `cert-manager.io/cluster-issuer` на Ingress?
3. Чем `SelfSigned` issuer отличается от `ACME` (Let's Encrypt)? В каких сценариях вы бы использовали каждый из них?

---

## Часть 4: Troubleshooting — боевые инциденты

Работа с Ingress и сертификатами полна подводных камней. В этом разделе мы разберем самые частые проблемы, с которыми инженеры сталкиваются в production, и алгоритмы их решения.

### Теория для изучения перед частью

#### Алгоритм диагностики проблем Ingress/TLS

Ветвление диагностики обычно выглядит так:

```text
Проблема с доступом к приложению через Ingress
│
├─ Выполняем `kubectl get ingress`
│     ├─ Поле ADDRESS пустое ? ───► Ошибка в ingressClassName, контроллер не запущен, либо проблема с LoadBalancer.
│     └─ ADDRESS есть ───► Идем дальше.
│
├─ Запрос выдает 404 Not Found ? ──► Контроллер работает, но не видит подходящего правила (host/path).
│     │                              Проверьте опечатки в host, правильность pathType и наличие rewrite-target.
│
├─ Запрос выдает 502/503/504 ? ────► Контроллер нашел правило, но бэкенд недоступен.
│     │                              Проверьте `kubectl get endpoints <service>` и статус подов приложения.
│
└─ Проблема с HTTPS (сертификат невалиден или соединение сброшено) ?
      ├─ Сертификат самоподписанный? ──► Используйте curl -k для тестов.
      └─ Сертификат вообще не выпущен? ──► Проверьте `kubectl get certificate` и `kubectl describe certificate`.
```

### Инцидент 1: Ingress не получает IP-адрес (ADDRESS пуст)

**Симптом:** При выполнении `kubectl get ingress` поле `ADDRESS` остается пустым длительное время (минуты и более), а Ingress не работает.

**Воспроизведение и диагностика:**
Создадим заведомо сломанный Ingress.

```yaml
# Файл broken/scenario-01/broken-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: broken-routing
spec:
  ingressClassName: typo-nginx # ОПЕЧАТКА!
  rules:
  - host: broken.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-a
            port:
              number: 80
```

```bash
# Применяем сломанный манифест
kubectl -n lab apply -f broken/scenario-01/broken-ingress.yaml

# Проверяем адрес
kubectl -n lab get ingress broken-routing
```
Вывод покажет пустое поле `ADDRESS`.

**Причина:** Ingress-контроллер игнорирует этот объект, так как `ingressClassName` (`typo-nginx`) не совпадает с его классом (`nginx`). Контроллер считает, что этот Ingress предназначен для какого-то другого контроллера.

**Решение:** 
Убедитесь, что класс Ingress совпадает с настроенным в кластере (можно проверить через `kubectl get ingressclass`). Отредактируйте Ingress и исправьте класс на `nginx`.

```bash
kubectl -n lab patch ingress broken-routing -p '{"spec":{"ingressClassName":"nginx"}}'
# Через пару секунд ADDRESS заполнится
kubectl -n lab get ingress broken-routing
```

### Инцидент 2: Ошибка 404 Not Found (default backend)

**Симптом:** При попытке открыть URL в браузере или через curl, вы получаете страницу с надписью `404 Not Found` и заголовком `Server: nginx`.

**Диагностика:**
Это классическая ошибка "Default Backend". Она означает, что сам Ingress-контроллер работает отлично и принял ваш запрос, но не нашел ни одного правила (`host` + `path`), под которое этот запрос подпадает.

**Причины и Решения:**
1. **Неверный `host`**: Вы обращаетесь к IP контроллера, но не передаете нужный заголовок Host.
   *Решение:* При тестировании через curl всегда используйте `--resolve host:port:ip` вместо обращения напрямую по IP. В браузере убедитесь, что домен добавлен в `/etc/hosts` или разрешается DNS.
2. **Опечатка в `path`**: Ingress настроен на `/api`, а вы обращаетесь к `/api/v1`. Если `pathType` стоит `Exact`, совпадения не будет.
   *Решение:* Измените `pathType` на `Prefix`.
3. **Отсутствие `rewrite-target`**: Ingress перенаправляет `/app` на бэкенд, но бэкенд ничего не знает про `/app` и ищет файлы в корне `/`. Бэкенд возвращает 404.
   *Решение:* Добавьте аннотацию `nginx.ingress.kubernetes.io/rewrite-target: /`.

### Инцидент 3: Ошибка SSL certificate problem: self-signed certificate

**Симптом:** При доступе через HTTPS команда `curl` отказывается работать и возвращает ошибку `curl: (60) SSL certificate problem: self-signed certificate`.

**Причина:** Вы используете самоподписанный сертификат (SelfSigned Issuer). Ваша операционная система или браузер не доверяют этому сертификату, так как он не подписан известным публичным удостоверяющим центром (таким как Let's Encrypt, DigiCert и т.д.).

**Решение:**
- **Для локального тестирования и разработки:** Добавьте флаг `-k` (или `--insecure`) в `curl`, чтобы отключить проверку цепочки доверия. В браузере нажмите "Advanced" -> "Proceed to site (unsafe)".
- **Для Production:** Используйте `ACME Issuer` (Let's Encrypt) в cert-manager. Он выпустит сертификат, которому будут доверять все современные браузеры и клиенты по умолчанию.

### Инцидент 4: Сертификат не выпускается (Certificate не переходит в Ready)

**Симптом:** Вы добавили аннотации `cert-manager` на Ingress, но HTTPS не работает. `kubectl get certificate` показывает `READY=False` или сертификат вообще не появляется.

**Диагностика:**
Поиск проблемы нужно вести сверху вниз: Ingress -> Certificate -> CertificateRequest -> Order -> Challenge (если используется ACME).

```bash
# 1. Проверяем наличие Certificate
kubectl -n lab get certificate

# 2. Если Ready=False, смотрим события (Events)
kubectl -n lab describe certificate <имя-сертификата>

# 3. Если проблема в Issuer, проверяем его статус
kubectl describe clusterissuer selfsigned-issuer
```

**Частые причины:**
- Опечатка в имени Issuer в аннотации `cert-manager.io/cluster-issuer: "wrong-name"`. Certificate даже не будет создан.
- Если используется Let's Encrypt (ACME HTTP-01 challenge): Ingress-контроллер недоступен из интернета (серверы Let's Encrypt не могут достучаться до вашего домена для проверки).
- Отсутствуют права (RBAC) у cert-manager.
- Не указан `secretName` в блоке `spec.tls` ресурса Ingress.

---

## Проверка модуля

Для автоматической проверки успешности выполнения задания запустите специальный проверочный скрипт:

```bash
bash verify/verify.sh
```

Этот скрипт автоматически проверит:
1. Наличие namespace `lab`.
2. Готовность и работоспособность бэкендов (`web-a`, `web-b`).
3. Корректность настройки Ingress-ресурсов (наличие правильного `ingressClassName=nginx`).
4. Работоспособность Ingress-контроллера (маршрутизация трафика).
5. Успешный автоматический выпуск сертификата cert-manager-ом и создание Secret `auto-tls`.

---

## Финальная карта ресурсов модуля

Все ресурсы, которые мы развернули и изучили в рамках этой лабораторной работы, сведены в таблицу:

| Имя ресурса | Относится к части | Описание и что демонстрирует |
|-------------|-------------------|------------------------------|
| `web-a` / `web-b` | Часть 1 | Базовые бэкенды (Deployment + Service + ConfigMap) с разным контентом |
| `web-routing` | Часть 1 | Ingress с демонстрацией host-based роутинга (a.lab.local / b.lab.local) |
| `web-paths` | Часть 1 | Ingress с демонстрацией path-based роутинга (/a, /b) + аннотация rewrite |
| `secure-tls` | Часть 2 | Ручная настройка TLS: Ingress + вручную сгенерированный Secret (`kubernetes.io/tls`) |
| `selfsigned-issuer` | Часть 3 | ClusterIssuer от cert-manager: определяет, КТО выдаёт сертификаты |
| `auto-tls` | Часть 3 | Автоматический TLS: Ingress + автоматически созданные Certificate и Secret через ingress-shim |
| `broken-routing` | Часть 4 | Troubleshooting: Ingress с неверным `ingressClassName`, демонстрирующий проблему "пустого ADDRESS" |

---

## Теоретические вопросы (итоговые)

Для закрепления материала ответьте на следующие вопросы.

### Блок 1: Ingress и маршрутизация
1. Каков полный жизненный цикл запроса от браузера пользователя до пода бэкенда при использовании Ingress? Какие компоненты Kubernetes участвуют в этом пути?
2. В чём заключается концептуальная разница между маршрутизацией на основе хоста (Host-based) и маршрутизацией на основе пути (Path-based)? Можно ли их комбинировать в одном Ingress-ресурсе?
3. Объясните своими словами, для чего нужна аннотация `nginx.ingress.kubernetes.io/rewrite-target`. Что произойдет, если направить запрос `/frontend/css/style.css` на бэкенд без этой аннотации?

### Блок 2: TLS и сертификаты
4. Объясните механизм TLS termination на Ingress-контроллере. Зачем терминировать TLS на балансировщике, а не передавать зашифрованный трафик напрямую в поды?
5. Как Ingress-контроллер определяет, какой именно сертификат предоставить клиенту во время TLS рукопожатия, если на одном IP-адресе (контроллере) обслуживается 100 разных доменов? Какая технология за это отвечает?
6. Почему браузеры и утилита `curl` по умолчанию выдают ошибку безопасности при подключении к нашему домену `secure.lab.local`?

### Блок 3: cert-manager
7. Какую роль в архитектуре cert-manager выполняют ресурсы `Issuer` (или `ClusterIssuer`) и `Certificate`? Чем они отличаются друг от друга?
8. Как работает механизм ingress-shim? Опишите, как добавление одной строки аннотации в Ingress приводит к появлению готового сертификата.

### Блок 4: Troubleshooting
9. Вы выполнили команду `kubectl get ingress` и видите, что поле `ADDRESS` пустое уже 5 минут. Назовите две самые вероятные причины такого поведения.
10. Ваш запрос к Ingress возвращает `404 Not Found` от NGINX. Как вы будете искать причину этой ошибки?

---

## Практические задания (отработка)

> Для глубокого понимания настоятельно рекомендуется выполнить эти задания на живом кластере. Проверяйте себя командами из шпаргалки и скриптом `verify/verify.sh`.

1. **Разведение трафика**: Создайте новый Ingress, который будет направлять запросы на хост `test.lab.local`, где путь `/appA` идет на `web-a`, а `/appB` идет на `web-b`. Обязательно используйте `rewrite-target`. Проверьте работоспособность через curl.
2. **Ручной TLS**: Сгенерируйте self-signed сертификат для нового домена `custom.lab.local`. Создайте Secret и Ingress. Убедитесь с помощью `curl -v`, что отдаётся именно ваш сертификат с правильным полем Subject.
3. **cert-manager в деле**: Разверните новое приложение (например, nginx) и настройте Ingress для `super.lab.local`. Повесьте аннотацию `cert-manager.io/cluster-issuer: "selfsigned-issuer"` и убедитесь, что Secret создаётся самостоятельно.
4. **Ремонт (Troubleshooting)**: Примените манифест `broken/scenario-01/broken-ingress.yaml`. Убедитесь, что Ingress не получает IP адрес. Затем исправьте манифест (почините `ingressClassName`), примените и убедитесь, что маршрутизация заработала.
5. **Проверка конфликтов**: Попробуйте создать два разных Ingress ресурса, которые пытаются повесить разные TLS сертификаты на одну и ту же комбинацию host+path. Изучите логи ingress-контроллера, чтобы увидеть, как он реагирует на такие конфликты.

---

## Шпаргалка

Команды, которые всегда должны быть под рукой при работе с Ingress и сертификатами:

```bash
# === Базовые проверки Ingress ===
# Узнать IP контроллера (при использовании NodePort/ClusterIP)
CIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

# Посмотреть доступные классы Ingress в кластере
kubectl get ingressclass

# Просмотр статуса Ingress, Certificate и Secret в namespace lab
kubectl -n lab get ingress,certificate,secret

# === Тестирование роутинга без DNS (через curl) ===
# HTTP запрос (подстановка нужного IP для домена)
kubectl -n lab run c --image=curlimages/curl:8.10.1 --restart=Never -i --rm -- \
  curl -s --resolve a.lab.local:80:$CIP http://a.lab.local/

# HTTPS запрос с игнорированием невалидного сертификата
kubectl -n lab run c --image=curlimages/curl:8.10.1 --restart=Never -i --rm -- \
  curl -sk --resolve secure.lab.local:443:$CIP https://secure.lab.local/

# HTTPS запрос с выводом деталей сертификата (Subject и Issuer)
kubectl -n lab run c --image=curlimages/curl:8.10.1 --restart=Never -i --rm -- \
  curl -skv --resolve secure.lab.local:443:$CIP https://secure.lab.local/ 2>&1 | grep -i 'subject:\|issuer:'

# === Ручная работа с TLS ===
# Генерация Self-Signed сертификата с учетом SAN (Subject Alternative Name)
openssl req -x509 -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem -subj "/CN=mydomain.local" -addext "subjectAltName=DNS:mydomain.local"
# Создание Secret из ключей
kubectl -n lab create secret tls my-tls-secret --cert=cert.pem --key=key.pem

# === Работа с cert-manager ===
# Просмотр доступных Issuer
kubectl get clusterissuer
kubectl -n lab get issuer

# Просмотр событий (Events) выпуска сертификата (незаменимо при дебаге)
kubectl -n lab describe certificate auto-tls
```

---

## Чему вы научились

В этом расширенном модуле вы освоили следующие важные навыки:
- Развертывание и настройка Ingress-ресурсов для маршрутизации трафика (host-based и path-based).
- Использование аннотаций, в частности `rewrite-target`, для адаптации путей под бэкенды.
- Понимание принципов TLS termination и SNI.
- Ручное создание TLS сертификатов и управление объектами Secret типа `kubernetes.io/tls`.
- Полная автоматизация выпуска и ротации SSL-сертификатов с помощью `cert-manager` и механизма `ingress-shim`.
- Диагностика и устранение типовых проблем (Troubleshooting) с Ingress и сертификатами, таких как ошибка 404, пустой ADDRESS и проблемы с доверием к сертификату.

## Уборка

Для полной очистки ресурсов, созданных в рамках данного модуля (включая Ingress-объекты, сертификаты, секреты и приложения), используйте следующий блок команд:

```bash
# Удаление всех базовых манифестов
kubectl -n lab delete -f manifests/apps.yaml --ignore-not-found
kubectl -n lab delete -f manifests/ingress.yaml --ignore-not-found

# Удаление ручных TLS ресурсов
kubectl -n lab delete -f manifests/tls/ingress-tls.yaml --ignore-not-found
kubectl -n lab delete secret secure-tls --ignore-not-found

# Удаление ресурсов cert-manager (Ingress, Certificate, Secret, ClusterIssuer)
kubectl -n lab delete -f manifests/cert-manager/ingress-cm.yaml --ignore-not-found
kubectl -n lab delete secret auto-tls --ignore-not-found
kubectl delete -f manifests/cert-manager/clusterissuer.yaml --ignore-not-found

# Для полной очистки всего namespace lab (опционально)
kubectl delete ns lab --ignore-not-found
```

> **Внимание!** Существует также мощный скрипт очистки `bash verify/cleanup.sh`. Он может удалить системные операторы, такие как сам ingress-nginx-controller и cert-manager. Используйте его, только если вы полностью завершили работу с модулем и данные аддоны не требуются для других лабораторных работ на вашем кластере.
