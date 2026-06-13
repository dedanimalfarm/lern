# 03 — Whiteout: удаление файла из read-only слоя

## Задача
Удалить через `merged` файл, который есть только в `lower`, и увидеть механизм
удаления в overlay — **whiteout** (character device 0,0) в upper. Файл в lower при
этом физически остаётся.

## Проверка
```bash
# (в lower есть untouched.txt)
rm $B/merged/untouched.txt
ls -la $B/upper/untouched.txt        # тип файла и major,minor
ls $B/merged                          # есть ли там untouched.txt
cat $B/lower/untouched.txt            # жив ли он в lower
```

## Ожидаемый результат
```
c--------- 2 root root 0, 0 ... untouched.txt   # whiteout: char device 0,0
readme.txt                                        # в merged untouched.txt пропал
untouched                                         # но в lower он физически жив
```
Ядро при `readdir` видит whiteout в upper и скрывает одноимённый файл из lower.
Так `RUN rm` в Dockerfile «удаляет» файл из нижележащего слоя, не стирая сам слой.
