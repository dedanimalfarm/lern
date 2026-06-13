# 01 — Собрать overlay из слоёв

## Задача
Создать lower (read-only «слой образа»), upper (r/w), work и смонтировать overlay;
убедиться, что `merged` показывает объединённое дерево слоёв.

## Проверка
```bash
B=/lab/08; mkdir -p $B/{lower,upper,work,merged}
echo "from base layer" > $B/lower/readme.txt
sudo mount -t overlay overlay \
  -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" $B/merged
ls $B/merged; cat $B/merged/readme.txt
sudo umount $B/merged
```

## Ожидаемый результат
```
readme.txt
from base layer
```
`merged` — объединение слоёв; пока в нём только содержимое lower (upper пуст).
`workdir` и `upperdir` обязаны быть на одной ФС (иначе mount упадёт — см. scenario-01).
