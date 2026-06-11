# Lab 12: Введение в CNI (Container Network Interface) "На пальцах"

**CNI (Container Network Interface)** — это стандарт, который используют Kubernetes (через kubelet), Podman, CRI-O и другие runtime'ы для настройки сети в контейнерах.

Многие думают, что CNI — это какая-то сложная магия внутри Kubernetes (Calico, Flannel, Cilium). На самом деле, **CNI — это просто набор обычных исполняемых бинарных файлов (скриптов)**.

Когда Kubernetes хочет создать сеть для пода (контейнера), он:
1. Создает пустой Network Namespace.
2. Формирует JSON-конфигурацию сети.
3. Запускает бинарник CNI (например, `/opt/cni/bin/bridge`), передавая ему JSON через `stdin`, а параметры (какой namespace, имя интерфейса) — через переменные окружения!
4. Бинарник делает всю ту ручную работу с `ip link`, `ip addr`, которую мы делали в предыдущих лабах, и завершается.

В этой лабораторной мы скачаем официальные "референсные" плагины CNI и **вручную, без Kubernetes, вызовем CNI-плагин из Bash**, чтобы он настроил наш namespace!

## Запуск лабораторной
```bash
cd /root/lern/labs/linux-basics/networking/lab12_cni_intro
bash setup.sh
```

## Что делает скрипт `setup.sh`:
1. Скачивает и распаковывает официальные плагины CNI в папку `/opt/cni/bin/`. (Там лежат `bridge`, `vlan`, `host-local` и т.д.).
2. Создает пустой Network Namespace с именем `cni-ns`.
3. Создает JSON конфиг (настраиваем сеть `10.22.0.0/24` с типом `bridge` и IPAM плагином `host-local` для выдачи IP).
4. **САМОЕ ГЛАВНОЕ:** Вызывает бинарник `/opt/cni/bin/bridge` напрямую из консоли:
```bash
export CNI_COMMAND=ADD
export CNI_CONTAINERID=my-cni-container-123
export CNI_NETNS=/var/run/netns/cni-ns
export CNI_IFNAME=eth0
export CNI_PATH=/opt/cni/bin

cat my-cni-config.json | /opt/cni/bin/bridge
```

## Как проверить?
Зайдите в созданный namespace и проверьте его интерфейсы:
```bash
ip netns exec cni-ns ip addr
```
Вы увидите, что CNI-плагин автоматически создал мост (на хосте), создал `veth` пару, поместил один конец в namespace под именем `eth0`, выдал ему IP-адрес из диапазона `10.22.0.0/24` и даже настроил маршруты! То есть сделал ровно то же самое, что мы писали руками в Lab 6 (Linux Bridge), но в соответствии со стандартом CNI.

## Как "удалить" под/контейнер в парадигме CNI?
Kubernetes (или вы) просто вызывает тот же бинарник, но с командой `DEL`:
```bash
export CNI_COMMAND=DEL
export CNI_CONTAINERID=my-cni-container-123
export CNI_NETNS=/var/run/netns/cni-ns
export CNI_IFNAME=eth0
export CNI_PATH=/opt/cni/bin

cat my-cni-config.json | /opt/cni/bin/bridge
```
CNI плагин сам пойдет и удалит интерфейсы и освободит IP адрес в базе данных `host-local` IPAM.
Можете попробовать выполнить эти команды прямо в терминале!
