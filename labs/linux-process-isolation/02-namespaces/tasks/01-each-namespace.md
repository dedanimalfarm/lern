# 01 — Поднять шесть namespace и подтвердить по inode

## Задача
Создать каждый из шести ключевых namespace и доказать, что он новый — сравнив
inode `/proc/self/ns/<тип>` внутри с хостовым.

## Проверка
```bash
# эталон хоста
for n in uts pid mnt net ipc user; do printf "%-5s %s\n" "$n" "$(readlink /proc/self/ns/$n)"; done

# все шесть в одном процессе
sudo unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc \
  /bin/bash -c 'for n in uts pid mnt net ipc user; do printf "%-5s %s\n" $n $(readlink /proc/self/ns/$n); done'
```

## Ожидаемый результат
Все шесть inode внутри ОТЛИЧАЮТСЯ от хостовых, например:
```
uts   uts:[4026532301]      # на хосте было uts:[4026532220]
pid   pid:[4026532303]
mnt   mnt:[4026532300]
net   net:[4026532304]
ipc   ipc:[4026532302]
user  user:[4026531837]→user:[4026532299]
```
(номера у вас свои). Каждый «внутри ≠ хост» ⇒ процесс реально в шести новых
namespace. Сравнивайте именно с хостом, а не команды между собой: между
отдельными короткоживущими `unshare` ядро переиспользует номера inode.
