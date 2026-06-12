#!/bin/bash
if [ ! -f "solution.sql" ]; then echo "Файл solution.sql не найден!"; exit 1; fi
PGPASSWORD=secretpassword psql -h 127.0.0.1 -U postgres -d shop_db -f solution.sql > /dev/null 2>&1
if [ $? -eq 0 ]; then echo "PASS: Запросы выполнились без ошибок!"; else echo "FAIL: В запросах синтаксическая ошибка."; fi
