# 02 — Доказать, что chroot НЕ изолирует ничего, кроме ФС

## Задача
Показать на числах: PID, UTS (hostname), сеть и mount-namespace у процесса
внутри `chroot` — те же, что у хоста. `chroot` меняет только видимый корень.

## Проверка
```bash
# UTS: hostname внутри совпадает с хостовым
hostname
sudo chroot /lab/01-chroot/rootfs /bin/hostname

# Namespace-inode внутри и снаружи: совпадают ⇒ это ОДИН и тот же namespace
for ns in mnt pid net; do
  printf "%-4s host=%s  chroot=%s\n" "$ns" \
    "$(stat -L -c %i /proc/self/ns/$ns)" \
    "$(sudo chroot /lab/01-chroot/rootfs /bin/stat -L -c %i /proc/self/ns/$ns)"
done

# Сеть: внутри видны хостовые интерфейсы
sudo chroot /lab/01-chroot/rootfs /bin/ps | head -3
```

## Ожидаемый результат
```
mnt  host=4026532219  chroot=4026532219     <- РАВНЫ
pid  host=4026532221  chroot=4026532221     <- РАВНЫ
net  host=4026531840  chroot=4026531840     <- РАВНЫ
```
(числа inode у вас свои, важно ЧТО они совпадают). `ps` внутри показывает
процессы хоста (`systemd`, `init`, …). Вывод: чтобы изолировать PID/UTS/NET,
нужен механизм следующего этапа — **namespaces** (`02-namespaces`).
