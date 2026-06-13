# 02 — Copy-on-Write: запись не трогает lower

## Задача
Изменить через `merged` файл, который физически лежит в read-only `lower`, и
убедиться: оригинал в lower цел, а правка ушла в `upper` (copy-up).

## Проверка
```bash
# (overlay смонтирован из задания 01, в lower есть readme.txt = "from base layer")
echo "modified by container" > $B/merged/readme.txt
echo "lower: $(cat $B/lower/readme.txt)"
echo "upper: $(cat $B/upper/readme.txt)"
```

## Ожидаемый результат
```
lower: from base layer          # read-only слой НЕ изменился (CoW)
upper: modified by container     # правка скопирована в upper (copy-up)
```
Поэтому из одного образа можно запустить сотни контейнеров: общий lower + у каждого
свой маленький upper-дельта. `docker diff` показывает именно содержимое upper.
