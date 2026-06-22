# Лабораторная работа Ansible 1 - Настройка простого веб-сервера

⏱ **Время выполнения:** 20 минут | **Сложность:** Легкая

## Оглавление
1. [Теория](#теория)
2. [Пример: webservers.yml](#пример-webserversyml)
3. [Конфигурационный файл NGINX](#конфигурационный-файл-nginx)
4. [Создание простой веб-страницы](#создание-простой-веб-страницы)
5. [Создание группы веб-серверов](#создание-группы-веб-серверов)
6. [Запуск сценария](#запуск-сценария)
7. [Проверка модуля](#проверка-модуля)
8. [Troubleshooting — частые проблемы](#troubleshooting--частые-проблемы)
9. [Контрольные вопросы](#контрольные-вопросы)
10. [Уборка](#уборка)

## Теория

В этом примере мы настроим удалённый сервер для запуска простого веб-сервера с использованием Nginx. Ansible Playbooks (сценарии) описывают желаемое состояние управляемых узлов. Вы пишете их в формате YAML. 
Сначала мы создадим сценарий `webservers.yml`, который описывает необходимые задачи: установку Nginx, копирование конфигурационных файлов, загрузку шаблона главной страницы и перезапуск службы. Затем мы создадим все нужные для его работы файлы.

## Пример: webservers.yml

Создайте файл `webservers.yml` со следующим содержимым:

```yaml
---
- name: Настройка веб-сервера с Nginx
  hosts: webservers
  become: True
  tasks:
    - name: Убедиться, что Nginx установлен
      package:
        name: nginx
        update_cache: yes

    - name: Копировать конфигурационный файл Nginx
      copy:
        src: playbooks/files/nginx.conf
        dest: /etc/nginx/sites-available/default

    - name: Включить конфигурацию
      file:
        src: /etc/nginx/sites-available/default
        dest: /etc/nginx/sites-enabled/default
        state: link

    - name: Копировать файл index.html
      template:
        src: playbooks/templates/index.html.j2
        dest: /usr/share/nginx/html/index.html

    - name: Перезапустить Nginx
      service:
        name: nginx
        state: restarted
```

*Примечание: Обратите внимание, что пути в `src` были обновлены на `playbooks/files/nginx.conf` и `playbooks/templates/index.html.j2` для соответствия структуре директорий в последующих шагах.*

## Конфигурационный файл NGINX

Для выполнения сценария нужен дополнительный файл конфигурации NGINX. Этот файл изменяет стандартную конфигурацию для сервера, обслуживающего статичные файлы. 
Создайте директорию `playbooks/files/` и сохраните этот файл под именем `playbooks/files/nginx.conf`.

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server ipv6only=on;
    root /usr/share/nginx/html;
    index index.html index.htm;
    server_name localhost;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

## Создание простой веб-страницы

Теперь добавим простую веб-страницу. Ansible может генерировать HTML страницы с помощью шаблонов Jinja2. 
Создайте директорию `playbooks/templates/` и сохраните этот шаблон в файле `playbooks/templates/index.html.j2`.

```html
<html>
  <head>
    <title>Welcome to Ansible</title>
  </head>
  <body>
    <h1>Nginx is configured using Ansible</h1>
    <p>If you see this page, it means Ansible has successfully installed Nginx.</p>
    <p>Running on {{ inventory_hostname }}</p>
  </body>
</html>
```

## Создание группы веб-серверов

Для настройки группы веб-серверов создайте директорию `playbooks/inventory/` и файл реестра `playbooks/inventory/vagrant.ini`. Добавьте сервер `testserver` в группу `webservers`.

```ini
[webservers]
testserver ansible_port=2202

[webservers:vars]
ansible_user = vagrant
ansible_host = 127.0.0.1
ansible_private_key_file = .vagrant/machines/default/virtualbox/private_key
```

Проверьте, как группы настроены в инвентаре с помощью команды:

```bash
ansible-inventory -i playbooks/inventory/vagrant.ini --graph
```

## Запуск сценария

Запускайте сценарии с помощью команды `ansible-playbook`. Убедитесь, что вы находитесь в той же директории, что и файл `webservers.yml`:

```bash
ansible-playbook -i playbooks/inventory/vagrant.ini webservers.yml
```

### Ожидаемый результат:

```bash
PLAY [Настройка веб-сервера с Nginx] **********************************************

TASK [Gathering Facts] **********************************************************
ok: [testserver]

TASK [Убедиться, что Nginx установлен] ******************************************
changed: [testserver]

TASK [Копировать конфигурационный файл Nginx] ***********************************
changed: [testserver]

TASK [Включить конфигурацию] ****************************************************
ok: [testserver]

TASK [Копировать файл index.html] ***********************************************
changed: [testserver]

TASK [Перезапустить Nginx] ******************************************************
changed: [testserver]

PLAY RECAP **********************************************************************
testserver              : ok=6    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

После успешного выполнения сценария откройте веб-браузер и перейдите по адресу `http://localhost:8080` (если используете Vagrant с пробросом портов). Вы увидите страницу с сообщением, что Nginx был успешно установлен Ansible.

## Проверка модуля

Вы можете запустить автоматическую проверку корректности выполнения лабораторной работы. Скрипт проверит, все ли необходимые файлы были созданы и нет ли в них синтаксических ошибок:

```bash
./verify.sh
```

## Troubleshooting — частые проблемы

1. **Ошибка: `UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh..."}`**
   - **Причина**: Ansible не может подключиться к хосту. 
   - **Решение**: Проверьте, запущен ли ваш сервер (например, Vagrant через `vagrant up`), корректен ли путь к ключу `ansible_private_key_file` в инвентарном файле и открыт ли SSH-порт.

2. **Ошибка при копировании: `Could not find or access 'playbooks/files/nginx.conf'`**
   - **Причина**: Файл конфигурации или шаблон находятся не в той директории или не были созданы.
   - **Решение**: Убедитесь, что вы создали директории `playbooks/files` и `playbooks/templates` относительно того места, откуда запускаете `ansible-playbook`.

3. **Ошибка синтаксиса YAML: `Syntax Error while loading YAML.`**
   - **Причина**: В файле `webservers.yml` допущена ошибка форматирования. В YAML отступы играют критическую роль (используйте пробелы, а не символы табуляции).
   - **Решение**: Проверьте отступы в `webservers.yml`. Можно использовать проверку синтаксиса: `ansible-playbook --syntax-check webservers.yml`.

## Контрольные вопросы

1. В чём разница между модулями `copy` и `template` в Ansible? В каких ситуациях следует использовать каждый из них?
2. Для чего нужна директива `become: True` на уровне `play` или отдельной задачи? Что произойдёт, если её не указать при установке системного пакета Nginx?
3. Что такое `inventory_hostname` в шаблоне Jinja2 и откуда Ansible берет это значение в нашем случае?
4. Почему мы используем состояние `state: restarted` для модуля `service`, и в чём заключается потенциальный недостаток принудительного перезапуска службы при каждом запуске плейбука? (Подсказка: подумайте об использовании механизма `handlers` в Ansible).

## Уборка

Для того чтобы удалить созданные в ходе выполнения лабораторной работы файлы конфигураций, инвентаря и сам плейбук, выполните скрипт очистки:

```bash
./cleanup.sh
```
