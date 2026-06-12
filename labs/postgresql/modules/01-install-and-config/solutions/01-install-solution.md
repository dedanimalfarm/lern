# Решение: Задание 1

```bash
# 1. Установка
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql

# 2. Первичный вход и задание пароля
sudo -u postgres psql -c "\password postgres"
# (ввести пароль)

# 3. Настройка postgresql.conf
# Находим версию (например 14) и редактируем файл
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/14/main/postgresql.conf
# Либо редактируем вручную через nano / vim

# 4. Настройка pg_hba.conf
echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf

# 5. Перезапуск службы
sudo systemctl restart postgresql

# 6. Проверка
psql -h 127.0.0.1 -U postgres -W
```
