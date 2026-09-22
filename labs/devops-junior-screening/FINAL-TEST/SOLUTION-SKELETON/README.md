# Junior DevOps — тестовое задание

> Это скелет. Замените этот файл своим README по критериям Части D:
> «как поднять», «как проверить», «как удалить», раздел «Что я бы сделал на проде».

## Структура

| Путь | Часть | Что сюда кладётся |
|------|-------|-------------------|
| `ansible.cfg`, `inventory/hosts.ini` | A | подключение к VM |
| `playbooks/site.yml` | A | входная точка прогона |
| `roles/common/` | A | пользователь, sshd, пакеты, chrony, ufw, hostname |
| `roles/common/files/deploy.pub` | A | публичный ключ пользователя `deploy` |
| `observability/compose.yml` | B | Prometheus (+ Grafana по желанию) |
| `secrets/README.md`, `secrets/bootstrap.sh` | C | выбранный подход к секретам и команды reproduce |
| `docs/topology.md` | D | ASCII-схема стенда |
| `ADR-0001.md` | D | одно архитектурное решение и его обоснование |

## Как поднять

```bash
# TODO: команда прогона Ansible
```

## Как проверить

```bash
# TODO: команды проверки (идемпотентность, targets=up, чтение секрета)
```

## Как удалить

```bash
# TODO: teardown
```

## Что я бы сделал на проде

- TODO
