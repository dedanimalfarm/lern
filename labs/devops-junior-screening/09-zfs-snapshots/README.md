# 09 · ZFS — snapshots, datasets, send/recv

> Тема из вакансии: «ZFS (snapshots, datasets)» (как плюс).

## Цель и навыки

Понять, чем ZFS отличается от ext4+LVM (CoW + интегрированный volume manager + checksumming) и пощупать **снапшоты, клоны, send/recv** на учебном poole, собранном из loop-файлов.

После лабы ты:

- объясняешь модель ZFS: pool → vdev → dataset → block;
- умеешь делать `zpool create`, `zfs create`, `zfs set`, `zfs snapshot`, `zfs rollback`, `zfs clone`, `zfs send | zfs recv`;
- знаешь про ARC и **почему ZFS любит много RAM** (но t3.micro переживёт учебную нагрузку);
- понимаешь, **где ZFS — лучший выбор, а где — нет** (нет: маленькие сервера, контейнерные FS; да: бэкап-серверы, БД-volume, файл-сервера).

## Теоретический минимум

**Pool** — это группа дисков (vdev'ов), в которой ZFS хранит данные.
**vdev** — топологический элемент: mirror, raidz, single disk, log, cache. Pool — это конкатенация vdev'ов.
**Dataset** — логический «раздел» внутри pool с собственными свойствами (`compression`, `quota`, `recordsize`).
**Block** — CoW: записанный блок не перезаписывается, под изменение пишется новый блок, старый остаётся жить, пока на него ссылается какой-то snapshot.

**Snapshot** — атомарный moment-in-time снимок dataset'а. **Бесплатен** (это просто ссылка на «состояние блоков на момент T»), занимает место только по мере того, как старые блоки переписываются.

**Clone** — снапшот, к которому пристроена возможность записи. Тоже почти-бесплатен.

**send/recv** — потоковый формат сериализации snapshot'а. Можно перегнать через `ssh`, `nc`, файл. Поддерживает инкременты (`-i base@T1 base@T2`).

**ARC** — RAM-кеш ZFS. По дефолту до 50% RAM. На маленькой VM можно ограничить через `/etc/modprobe.d/zfs.conf` (`options zfs zfs_arc_max=536870912`).

## Базовая отработка

> **Внимание:** ZFS-модуль ставится из `zfsutils-linux` (DKMS), сборка ядра занимает несколько минут. На Ubuntu 24.04 пакет доступен из репо `universe`.

### Шаг 1. Установка

```bash
sudo apt-get update
sudo apt-get install -y zfsutils-linux
sudo modprobe zfs
lsmod | grep zfs
zfs version
```

### Шаг 2. Pool на loop-файлах

«Реальных» дисков на учебной VM нет — сделаем два loop-файла по 2 GB и соберём из них **mirror**.

```bash
sudo mkdir -p /var/lab/zfs
sudo truncate -s 2G /var/lab/zfs/disk1.img
sudo truncate -s 2G /var/lab/zfs/disk2.img

LO1=$(sudo losetup --find --show /var/lab/zfs/disk1.img)
LO2=$(sudo losetup --find --show /var/lab/zfs/disk2.img)
echo "loop: $LO1 $LO2"

sudo zpool create -f tank mirror $LO1 $LO2
sudo zpool status tank
sudo zfs list
df -h /tank
```

`zpool status` показывает `mirror-0` из двух loop-устройств. ZFS уже смонтировал dataset `tank` в `/tank`.

### Шаг 3. Datasets, свойства, квоты

```bash
sudo zfs create tank/projects
sudo zfs create tank/projects/alpha
sudo zfs create tank/projects/beta

sudo zfs set compression=zstd tank/projects
sudo zfs set quota=500M tank/projects/beta
sudo zfs get compression,quota,used,available -r tank/projects

# поиграйся со сжатием
sudo cp /var/log/syslog /tank/projects/alpha/syslog.copy
sudo zfs get compressratio tank/projects
```

> `compression=zstd` — почти всегда выгодно: чуть CPU, прилично экономии и **меньше I/O**.

### Шаг 4. Snapshots и rollback

```bash
echo "before snapshot" | sudo tee /tank/projects/alpha/file.txt
sudo zfs snapshot tank/projects/alpha@v1
echo "after snapshot" | sudo tee /tank/projects/alpha/file.txt
sudo zfs list -t snapshot

# заглянуть в снапшот через ZFS-FS
ls /tank/projects/alpha/.zfs/snapshot/v1/

# rollback к v1
sudo zfs rollback tank/projects/alpha@v1
cat /tank/projects/alpha/file.txt           # "before snapshot"
```

### Шаг 5. Clone

```bash
sudo zfs snapshot tank/projects/alpha@before-clone
sudo zfs clone tank/projects/alpha@before-clone tank/projects/alpha-test
ls /tank/projects/alpha-test/                # копия, можно править независимо
echo "fork branch" | sudo tee /tank/projects/alpha-test/file.txt

sudo zfs list -t all | grep alpha
```

### Шаг 6. send / recv

«Бэкап» dataset'а в другой pool/файл/хост:

```bash
sudo zfs snapshot tank/projects@daily-1
sudo zfs send tank/projects@daily-1 | gzip > /var/lab/zfs/projects.daily-1.zfs.gz

# инкремент
sleep 5
sudo zfs snapshot tank/projects@daily-2
sudo zfs send -i tank/projects@daily-1 tank/projects@daily-2 \
  | gzip > /var/lab/zfs/projects.daily-2.inc.zfs.gz
ls -lh /var/lab/zfs/*.gz
```

В реальной схеме поток уходит на другой хост: `zfs send … | ssh backup-host "zfs recv -F tank/backup/projects"`.

## Расширенная отработка

### Задача 1. Сравнение CoW и ext4

Создай dataset `tank/dbtest`, развороши на нём 200 МБ файлов с `dd if=/dev/urandom`. Сделай snapshot. Перезапиши те же файлы случайными данными. Размер snapshot'а покажет тебе **сколько изменилось** на блочном уровне — это и есть «честная стоимость хранения CoW-снапшота».

### Задача 2. send/recv через ssh с pv

```bash
# на источнике
sudo zfs send tank/projects@daily-1 \
  | pv -s $(sudo zfs send -nP tank/projects@daily-1 | awk '/size/ {print $2}') \
  | ssh ubuntu@<DEST> "sudo zfs recv -F tank/backup/projects"
```

`pv` даёт прогресс — на ночных репликациях критично, иначе не понимаешь, идёт ли передача.

### Задача 3. Замена «диска» (хардлесс-маневр)

Симулируй смерть одного из loop-устройств:

```bash
sudo zpool offline tank $LO2
sudo zpool status tank        # DEGRADED, но pool жив

# создаём «новый диск»
sudo truncate -s 2G /var/lab/zfs/disk3.img
LO3=$(sudo losetup --find --show /var/lab/zfs/disk3.img)
sudo zpool replace tank $LO2 $LO3
sudo zpool status tank        # resilvering → ONLINE
```

Это и есть «hot-swap диска без даунтайма» — главный аргумент за RAID/mirror.

## Acceptance criteria

- [ ] `zpool status tank` → ONLINE, mirror из двух vdev'ов.
- [ ] `zfs list -t snapshot` показывает ≥3 снапшота.
- [ ] `zfs rollback` возвращает прежнее содержимое файла.
- [ ] Полный + инкрементальный send-файлы созданы, размер инкремента **много меньше** полного.
- [ ] (Расширенная) `zpool replace` прошёл, статус `ONLINE` после resilver.

## Что обсудить на ревью

1. Чем ZFS лучше LVM+ext4 на бэкап-сервере? Что хуже на сервере БД с интенсивной перезаписью маленьких блоков?
2. Что такое **ARC**, **L2ARC**, **SLOG**? Когда они нужны?
3. Почему `zfs destroy <snap>` дешевле, чем удаление обычных файлов?
4. Можно ли запустить ZFS поверх HW-RAID? Почему лучше не надо?
5. Что значит `recordsize=128K` и когда его меняют (Postgres → 8K/16K)?

## Как погасить (важно!)

```bash
sudo zpool export tank
sudo losetup -d "$LO1" "$LO2" "$LO3" 2>/dev/null
sudo rm -rf /var/lab/zfs
```

Иначе при следующей загрузке ZFS попытается reimport, не найдёт устройств — будут шумные сообщения в `journalctl`.

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `cannot create 'tank': pool already exists` | прошлый прогон не очистили | `zpool destroy tank` + `losetup -d` |
| ARC съел всю память на маленькой VM | дефолт = 50% RAM | `options zfs zfs_arc_max=536870912` в `/etc/modprobe.d/zfs.conf` |
| `zfs: module not found` | DKMS не собрал | проверь `dkms status`, ядро headers (`linux-headers-$(uname -r)`) |
| Поломан после `apt upgrade` ядра | DKMS не пересобрался | `dkms autoinstall && update-initramfs -u && reboot` |
| `zfs send` пишет в `tty` мусор | забыл `gzip` / `| ssh ...` | redirect в файл или pipe |
