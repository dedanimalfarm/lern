# Пробный экзамен в формате LFCS

Контрольная точка после раздела [`1.live-in-terminal`](../1.live-in-terminal): 18 практических задач на навыки,
которые на экзамене LFCS нужны в каждом домене, — поиск, обработка текста, перенаправление, права и ACL,
архивы, ссылки, пользователи, sudo, окружение.

Формат повторяет настоящий экзамен:

| | Здесь | LFCS |
|---|---|---|
| Задачи | 18 | 17–20 |
| Время | 2 часа (verify.sh показывает, сколько прошло) | 2 часа |
| Справка | только `man`, `--help`, `help`, `/usr/share/doc` | man-страницы и `/usr/share/doc` |
| Права | `sudo -i` | `sudo -i` |
| Оценка | задача засчитывается целиком, порог — 67 из 100 | по результату на системе |

Это **не** весь LFCS: здесь нет задач на Git, systemd, сертификаты, сеть, LVM и прочие домены —
только базовые команды, на которых они строятся. Официальный список компетенций — на
[странице экзамена](https://training.linuxfoundation.org/certification/linux-foundation-certified-sysadmin-lfcs/).

## Стенд

`setup.sh` создаёт пользователей (`auditor`, `guest`, `webuser`) и данные в `/opt/exam`, а задачи меняют
`/etc/sudoers.d`, `/etc/profile.d` и создают пользователей. Поэтому нужна **одноразовая** машина:
учебная VM или docker-контейнер. Проверено на Ubuntu 22.04 и 24.04.

Вариант с docker (из каталога `labs/linux-basics`):

```bash
docker run -it --name lfcs-exam --hostname exam -v "$PWD/lfcs-mock-exam:/exam:ro" ubuntu:24.04 bash
# внутри контейнера:
apt-get update && apt-get install -y sudo acl xz-utils vim less man-db unminimize
yes | unminimize          # вернуть man-страницы — на экзамене они ваша единственная справка
                          # (в ubuntu:22.04 команда unminimize уже есть, пакет ставить не нужно)
cd /exam && ./setup.sh
```

На VM: скопируйте каталог `lfcs-mock-exam` и выполните `sudo ./setup.sh`.

`setup.sh` ничего не удаляет и не запускается второй раз: если `/opt/exam` уже есть, он откажется работать.
Для нового прогона создайте новый контейнер (`docker run ...` с другим `--name`) или откатите VM на снимок.

## Как сдавать

1. `./setup.sh` — время пошло.
2. Решайте задачи из [TASKS.md](TASKS.md) от root (`sudo -i`). Ответы-файлы — в `/opt/exam/answers/`.
3. `./verify.sh` — в любой момент и сколько угодно раз: скрипт только читает систему.
   Для каждой задачи он печатает `OK` или `FAIL` с первым невыполненным условием, в конце — сумму и время.

Решения с разбором ловушек — в [solutions/solve.sh](solutions/solve.sh). Откройте их после попытки.

## Для автора задач

- `ci-selftest.sh` — самопроверка на одноразовом стенде (так её запускает CI):
  - `./ci-selftest.sh` — на нетронутом стенде verify.sh даёт 0 баллов, после `solutions/solve.sh` — 100;
  - `./ci-selftest.sh mistakes` — после [типичных ошибок](tests/typical-mistakes.sh) каждая такая задача получает FAIL.
    Так проверяется, что ловушки работают: например, `grep IT` вместо отдела ровно `IT`, `ln -sf` без `-n`,
    `chmod o+r` вместо ACL, `export` в конце `~/.bashrc`.
- Новая задача добавляется в четырёх местах: условие в `TASKS.md`, данные в `setup.sh`, проверка `tNN` в
  `verify.sh`, решение в `solutions/solve.sh` — и, если у задачи есть ловушка, ошибка в `tests/typical-mistakes.sh`.
- `verify.sh` не должен ничего менять в системе: права проверяются через `runuser`, окружение — через `su -`.
- CI: workflow [`linux-basics-lint`](../../../.github/workflows/linux-basics-lint.yml) запускает оба режима
  самопроверки в контейнерах Ubuntu 22.04 и 24.04.
