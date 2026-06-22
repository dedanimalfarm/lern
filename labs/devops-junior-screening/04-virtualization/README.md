# 04 · Virtualization / контейнеры (Docker)

⏱ **Время на выполнение:** ~1.5 - 2 часа
📈 **Сложность:** Средняя

## Оглавление

- [Цель и навыки](#цель-и-навыки)
- [Теоретический минимум](#теоретический-минимум)
- [Базовая отработка](#базовая-отработка)
- [Расширенная отработка](#расширенная-отработка)
- [Бонус — KVM в одном абзаце](#бонус--kvm-в-одном-абзаце)
- [Troubleshooting — частые проблемы](#troubleshooting--частые-проблемы)
- [Проверка модуля](#проверка-модуля)
- [Контрольные вопросы](#контрольные-вопросы)
- [Уборка](#уборка)

> Тема из вакансии: «Опыт с виртуализацией или контейнерами: KVM / Proxmox / VMware **или** Docker». «Развёртывание виртуализации».

## Цель и навыки

В вакансии есть «или» — нам подходит Docker, потому что:

- t3.micro и большинство учебных VM **не имеют nested-virtualization** (KVM не запустится);
- следующие лабы (observability/secrets) — это контейнеры, в них же будет prom/grafana/vault/loki;
- понимание namespaces/cgroups, которое лежит в основе Docker, по объёму ровно то же, что хотят от джуна — без RA-сертификации Proxmox.

> Если у тебя есть отдельный bare-metal или VM с nested virt — в конце есть **бонус-раздел** про KVM, по той же логике (libvirt + virsh + один cloud-image гость).

После лабы ты умеешь:

- ставить docker engine на Ubuntu по официальной инструкции (без `snap`-фантомов);
- запускать контейнер с правильными `-p`, `-v`, `--restart`, `--network`;
- писать минимальный `Dockerfile` для python/go-сервиса;
- собирать стек через `docker compose` (V2, плагин), читать логи, делать `exec`;
- понимать **сети** Docker (bridge, host, none, user-defined) и видеть их в `ip link` хоста;
- понимать, что такое **volume** vs **bind-mount** и когда что;
- зачищать диск (`docker system prune -af --volumes`) — критично на t3.micro.

## Теоретический минимум

**Контейнер** — это процесс хоста, изолированный namespaces (pid/net/mnt/ipc/uts/user) и ограниченный cgroups. Образ — read-only layered FS (overlay2 поверх ext4). Docker — это runtime (containerd → runc) + UX.

**Поверх ядра нет VM.** Контейнер делит ядро с хостом — это не «лёгкая VM», это **процесс**. Отсюда: уязвимость ядра = выход из контейнера; нельзя поменять `sysctl` без `--privileged` (и даже с ним не всегда).

**Сети Docker:**

| Сеть          | Что делает                                           |
|---------------|------------------------------------------------------|
| `bridge`      | дефолтная, NAT через iptables/nft на интерфейс `docker0`. Все контейнеры на ней «видят» хост через шлюз `172.17.0.1`. |
| `host`        | контейнер сидит в netns хоста, без NAT. Быстро, но конфликты портов. |
| `none`        | netns без интерфейсов. Изоляция полная.              |
| user-defined  | как `bridge`, но с **встроенным DNS** между контейнерами по имени. Это то, что использует `docker compose`. |

**Volume vs bind-mount:** volume — Docker-managed (`/var/lib/docker/volumes/`), переносится между хостами, есть бэкапы. bind-mount (`-v /host/path:/container/path`) — прямой проброс, проще для разработки, но привязан к путям хоста.

**`docker compose`** — декларативное описание стека (несколько контейнеров + сети + volumes) в YAML. С 2023 года — плагин `docker-compose-plugin`, команда `docker compose` (без дефиса).

## Базовая отработка

### Шаг 1. Поставить Docker по официальному гайду

На AWS EC2 в Ubuntu есть «snap docker» — это **не то**, что нам нужно (медленный, странный). Ставим из репо Docker:

```bash
sudo apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $CODENAME stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker          # применить группу в текущей сессии (или перелогинься)

docker version
docker compose version
```

### Шаг 2. Hello-world и анатомия

```bash
docker run --rm hello-world
docker run --rm -it alpine:3.20 sh -c 'cat /etc/os-release; id; ps -ef'
docker run --rm alpine:3.20 ip -br addr     # 172.17.0.2 или подобный
ip -br link | grep docker                   # docker0 = bridge на хосте
sudo iptables -t nat -S | grep -i docker | head
```

> Смотри: контейнер видит только себя в `ps -ef` — это pid-namespace.

### Шаг 3. Постоянный сервис с портом и volume

```bash
docker run -d --name web \
  --restart=unless-stopped \
  -p 8080:80 \
  -v web-content:/usr/share/nginx/html \
  nginx:alpine

curl -s http://127.0.0.1:8080 | head -5
docker exec -it web sh -c 'echo "<h1>Lab 04</h1>" > /usr/share/nginx/html/index.html'
curl -s http://127.0.0.1:8080
docker logs web --tail 5
docker stop web && docker rm web
# volume пережил
docker volume ls | grep web-content
docker run --rm -v web-content:/data alpine cat /data/index.html
docker volume rm web-content
```

### Шаг 4. Свой Dockerfile

```bash
mkdir -p ~/lab04/app && cd ~/lab04/app
cat > app.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer
import os, socket
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(f"hi from {socket.gethostname()} v={os.getenv('APP_VER','dev')}\n".encode())
HTTPServer(("0.0.0.0", 8000), H).serve_forever()
EOF

cat > Dockerfile <<'EOF'
FROM python:3.12-alpine
WORKDIR /app
COPY app.py .
USER 65534:65534
EXPOSE 8000
ENV APP_VER=1.0.0
CMD ["python", "app.py"]
EOF

docker build -t lab04/app:1.0.0 .
docker run --rm -d --name app -p 8000:8000 lab04/app:1.0.0
curl -s http://127.0.0.1:8000
docker stop app
```

> Обрати внимание: `USER 65534` (nobody). Никогда не запускай контейнер от root, если можешь не от root. На код-ревью это первое, что смотрят.

### Шаг 5. compose: два сервиса с user-defined network

```bash
cd ~/lab04
cat > compose.yml <<'EOF'
services:
  app:
    image: lab04/app:1.0.0
    environment:
      APP_VER: 1.1.0
    networks: [internal]
  proxy:
    image: nginx:alpine
    ports: ["8081:80"]
    networks: [internal]
    volumes:
      - ./proxy.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on: [app]
networks:
  internal:
EOF

cat > proxy.conf <<'EOF'
server {
  listen 80;
  location / {
    proxy_pass http://app:8000;
    proxy_set_header Host $host;
  }
}
EOF

docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8081
docker compose logs --tail 20
docker compose down
```

> `proxy` обращается к `app` по DNS-имени `app` — это магия user-defined-сети. На дефолтной `bridge`-сети так не работает.

## Расширенная отработка

### Задача 1. Минимум привилегий

Перепиши свой Dockerfile с принципами:

- многослойная сборка `FROM python:3.12-alpine AS build` → `FROM gcr.io/distroless/python3-debian12 AS runtime`;
- `--read-only` rootfs;
- drop всех capabilities (`--cap-drop=ALL`);
- `--security-opt=no-new-privileges`;
- проверь, что контейнер **всё равно** работает и отвечает на `curl`.

Команда запуска:

```bash
docker run --rm -d --name app \
  --read-only --tmpfs /tmp \
  --cap-drop=ALL --security-opt=no-new-privileges \
  -p 8000:8000 lab04/app:1.0.0
```

### Задача 2. Карта сети «куда едет пакет»

Запусти 2 контейнера в дефолтной `bridge` и трассируй пакет с `app` до `proxy`:

```bash
docker run -d --name app lab04/app:1.0.0
docker run -d --name proxy --link app nginx:alpine
docker exec app ip route get $(docker inspect proxy -f '{{ .NetworkSettings.IPAddress }}')
sudo iptables -t nat -S DOCKER | head
sudo nft list ruleset | grep -A3 'chain docker'
```

Объясни своими словами: где NAT, где FORWARD-rules, какой смысл `docker0`.

### Задача 3. Чистка диска

На t3.micro `/var/lib/docker` распухает за минуты. Запомни:

```bash
docker system df             # сколько что занимает
docker system prune -af      # удалить остановленные контейнеры, висячие образы, build cache
docker volume prune -f       # NB: убьёт неиспользованные volume — данные тоже
```

Поставь это **до** того, как закроешь сессию.

## Бонус — KVM в одном абзаце

На bare-metal или VM с nested virt:

```bash
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils
sudo usermod -aG libvirt,kvm $USER && newgrp libvirt
sudo virsh net-list --all
virt-install --name guest1 --memory 1024 --vcpus 1 \
  --disk size=5 --location http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/ \
  --network network=default --graphics none --extra-args 'console=ttyS0'
sudo virsh list --all
sudo virsh shutdown guest1 && sudo virsh undefine --remove-all-storage guest1
```

`virsh` — это `kubectl` для libvirt, выучи 5 команд: `list`, `start`, `shutdown`, `destroy` (force-kill), `console`.

## Troubleshooting — частые проблемы

| Симптом / Ошибка | Причина | Лечение |
|---------|---------|---------|
| `permission denied while trying to connect to the Docker daemon socket` | Пользователь не в группе `docker` | Выполнить `sudo usermod -aG docker $USER` и перелогиниться (или `newgrp docker`) |
| `bridge` контейнеры не резолвят друг друга по имени | дефолтная bridge сеть не предоставляет встроенный DNS | Создать user-defined network (`docker network create ...`) или использовать `docker compose` |
| `docker compose: command not found` | Установлена старая версия `docker-compose` или snap | Установить пакет `docker-compose-plugin` из официального репозитория Docker |
| Полный диск (`No space left on device`) | Скопилось много старых образов и volume'ов | `docker system prune -af --volumes` |
| `iptables: command not found` после установки Docker | dockerd сам ставит правила через nft на Ubuntu 24.04 | Использовать `sudo nft list ruleset` вместо `iptables -S` |
| Порт уже занят (`Bind for 0.0.0.0:80 failed: port is already allocated`) | Какой-то процесс (например, nginx хоста или другой контейнер) уже слушает этот порт | Поменять порт проброса (`-p 8080:80`) или остановить процесс, занимающий порт (`sudo netstat -tlpn` / `sudo ss -tlpn`) |
| Контейнер сразу падает после запуска (статус `Exited (1)`) | Процесс завершился с ошибкой или отсутствует foreground-задача | Проверить логи контейнера командой `docker logs <container_name>` |

## Проверка модуля

Чтобы убедиться, что модуль пройден корректно, запустите скрипт проверки:

```bash
./verify.sh
```

Он проверит наличие необходимых файлов (Dockerfile, app.py, compose.yml, proxy.conf), установку Docker и собранный образ приложения.

## Контрольные вопросы

1. **Изоляция:** Почему контейнер — не виртуальная машина (VM)? В каких сценариях вам всё равно потребуется использовать KVM или Firecracker для запуска стороннего кода?
2. **Файловая система:** Что такое драйвер `overlay2` и как Docker добавляет слои в образ? Почему размер контейнера может расти при записи файлов, если образ read-only?
3. **Безопасность:** Зачем использовать `--cap-drop=ALL`? Какие capabilities нужны обычным веб-сервисам? Почему не стоит запускать процессы в контейнере от пользователя `root`?
4. **Сети:** В чём разница между инструкцией `EXPOSE` в `Dockerfile` и флагом `-p` при выполнении `docker run`? Можно ли обратиться к порту `EXPOSE` извне без `-p`?

## Уборка

По завершении лабораторной работы, вызовите скрипт очистки для удаления созданных контейнеров, volume-ов и директорий:

```bash
./cleanup.sh
```

Скрипт полностью удалит рабочую директорию `~/lab04` и очистит Docker от остановленных контейнеров и неиспользуемых сетей. Убедитесь, что больше не нуждаетесь в результатах лабы перед его запуском.
