#!/bin/bash
set -euo pipefail

echo "==> Проверка выполнения модуля: Циклы и условные выражения в Bash"

# Task 1
if [ ! -x "./task1_loops.sh" ]; then
    echo "❌ Ошибка: ./task1_loops.sh не найден или не является исполняемым."
    exit 1
fi
echo "✅ task1_loops.sh найден."

task1_out=$(./task1_loops.sh || true)
if echo "$task1_out" | grep -q "1 2 3 4 5 6 7 8 9 10"; then
    echo "✅ task1_loops.sh работает корректно."
else
    echo "❌ Ошибка в task1_loops.sh: нет ожидаемого вывода."
    exit 1
fi

# Task 2
if [ ! -x "./task2_check.sh" ]; then
    echo "❌ Ошибка: ./task2_check.sh не найден или не является исполняемым."
    exit 1
fi
echo "✅ task2_check.sh найден."

touch test_file_for_task2.txt
task2_out=$(./task2_check.sh test_file_for_task2.txt || true)
if echo "$task2_out" | grep -q -i "Это файл"; then
    echo "✅ task2_check.sh корректно определяет файл."
else
    echo "❌ Ошибка в task2_check.sh: некорректно определяет файл."
    rm -f test_file_for_task2.txt
    exit 1
fi
rm -f test_file_for_task2.txt

# Task 3
if [ ! -x "./task3_case.sh" ]; then
    echo "❌ Ошибка: ./task3_case.sh не найден или не является исполняемым."
    exit 1
fi
echo "✅ task3_case.sh найден."
task3_out=$(./task3_case.sh "Пятница" || true)
if echo "$task3_out" | grep -q "Почти выходные"; then
    echo "✅ task3_case.sh работает корректно."
else
    echo "❌ Ошибка в task3_case.sh: некорректный ответ для Пятницы."
    exit 1
fi

# Task 4
if [ ! -x "./task4_table.sh" ]; then
    echo "❌ Ошибка: ./task4_table.sh не найден или не является исполняемым."
    exit 1
fi
echo "✅ task4_table.sh найден."
task4_out=$(./task4_table.sh || true)
if echo "$task4_out" | grep -q "5 \* 5 = 25" || echo "$task4_out" | grep -q "5 \* 5=25" || echo "$task4_out" | grep -q "25"; then
    echo "✅ task4_table.sh работает корректно."
else
    echo "❌ Ошибка в task4_table.sh: нет ожидаемого вывода '5 * 5 = 25'."
    exit 1
fi

echo "🎉 Все основные задания выполнены верно!"
