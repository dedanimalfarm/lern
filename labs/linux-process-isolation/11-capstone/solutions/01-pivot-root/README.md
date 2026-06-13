# Решение scenario-01: pivot_root + новый mount-namespace

Чтобы «контейнер» перестал быть дырявым chroot, нужен новый mount-namespace и смена
корня через `pivot_root` с удалением старого корня:

```bash
unshare --mount ... # новый mnt-ns (этап 02)
cd <merged>; pivot_root . old_root
umount -l old_root  # старый (хостовый) корень исчезает из дерева (этап 03)
```

Ровно это делает `mycontainer.sh`. После этого `/proc/1/root` ведёт в корень
контейнера, и побег закрыт:

```bash
sudo 11-capstone/broken/scenario-01/make-broken.sh    # наивный chroot → побег на ХОСТ
sudo 11-capstone/solutions/01-pivot-root/fix.sh         # mycontainer → побег закрыт (alpine)
```

Это главный вывод курса: контейнер от chroot отличают namespaces + `pivot_root`,
а не «магия» Docker. Настоящие рантаймы (`runc`, этап 13) делают ту же
последовательность системных вызовов.
