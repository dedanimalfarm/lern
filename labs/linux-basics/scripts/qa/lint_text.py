#!/usr/bin/env python3
"""Текстовый линт лабораторных linux-basics.

Ловит дефекты, которых не видно глазами, но которые ломают задания на практике.
Все четыре класса реально встречались в 1.live-in-terminal (исправлены в октябре 2026):

  crlf          окончания строк CRLF. Лишний \\r в конце строки: grep 'x$' перестаёт
                находить строки (system.log: 0 совпадений вместо 240), wc -m считает
                лишние символы, \\r попадает в последнее поле cut/awk и в md5sum.
  eof-newline   нет \\n в конце файла. wc -l считает символы \\n, поэтому последняя
                строка не учитывается (4.grep/file.txt: 15 строк вместо 16).
  utf8          файл не в UTF-8 — кириллица превращается в мусор.
  path-ascii    не-ASCII символ в имени файла или каталога. В 19.сut-and-paste первая
                «с» была кириллической: cd 19.cut<Tab> каталог не находил.
  cyr-flag      кириллическая буква сразу после дефиса опции: «grep -С 2» набрано
                кириллической С и падает с "invalid option".
  mixed-script  слово, где латиница смешана с кириллицей (grеp с кириллической «е»):
                такая команда выглядит правильно, но не запускается.

Использование (из labs/linux-basics):
  python3 scripts/qa/lint_text.py 1.live-in-terminal   # проверить раздел
  python3 scripts/qa/lint_text.py --self-test          # убедиться, что каждый класс ловится

Проверяются только файлы, отслеживаемые git (git ls-files), — чтобы файлы, которые
студент создал во время заданий, не мешали. Вне git-репозитория обходится весь каталог.
Код возврата: 0 — чисто, 1 — есть находки, 2 — ошибка запуска.
Только стандартная библиотека Python 3.8+.
"""
import os
import re
import subprocess
import sys

# Диапазон кириллицы в Unicode (U+0400–U+04FF): А–я, Ё/ё и прочие буквы блока.
CYR = "Ѐ-ӿ"
# Дефис опции в начале строки или после пробела/кавычки/скобки/пайпа, за ним 1–2 дефиса
# и сразу кириллическая буква: «-С», «--е». Тире «—» (U+2014) сюда не попадает.
CYR_FLAG_RE = re.compile(r"(?:^|(?<=[\s`'\"(|]))--?[" + CYR + r"]", re.MULTILINE)
# «Слово» — непрерывная последовательность латинских и кириллических букв.
WORD_RE = re.compile(r"[A-Za-z" + CYR + r"]+")
LATIN_RE = re.compile(r"[A-Za-z]")
CYR_RE = re.compile(r"[" + CYR + r"]")


def check_content(rel_path, data):
    """Вернуть список находок (rule, line, message) для одного файла.

    rel_path — путь относительно проверяемого каталога, data — байты файла.
    Функция чистая (не трогает диск), поэтому её же использует --self-test.
    """
    findings = []

    if any(ord(ch) > 127 for ch in rel_path):
        bad = "".join(ch for ch in rel_path if ord(ch) > 127)
        findings.append(("path-ascii", 0,
                         "не-ASCII символы в имени пути: %r (кириллица вместо латиницы?)" % bad))

    if b"\0" in data:          # бинарный файл: текстовые правила к нему неприменимы
        return findings
    if not data:               # пустой файл (например, заготовка для cp/mv) — это нормально
        return findings

    if b"\r" in data:
        line = data[:data.index(b"\r")].count(b"\n") + 1
        total = data.count(b"\r")
        findings.append(("crlf", line,
                         "символ \\r (CRLF) — %d шт., первый в этой строке; нужен LF" % total))

    if not data.endswith(b"\n"):
        lines = data.count(b"\n") + 1
        findings.append(("eof-newline", lines,
                         "нет \\n в конце файла — wc -l не посчитает последнюю строку"))

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        line = data[:exc.start].count(b"\n") + 1
        findings.append(("utf8", line, "файл не в UTF-8: %s" % exc.reason))
        return findings

    for m in CYR_FLAG_RE.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        findings.append(("cyr-flag", line,
                         "кириллическая буква в опции команды: %r" % m.group(0)))

    for m in WORD_RE.finditer(text):
        word = m.group(0)
        if LATIN_RE.search(word) and CYR_RE.search(word):
            line = text.count("\n", 0, m.start()) + 1
            findings.append(("mixed-script", line,
                             "латиница и кириллица в одном слове: %r" % word))

    return findings


def list_files(root):
    """Отслеживаемые git файлы внутри root (пути относительно root)."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-z", "--", "."],
            check=True, capture_output=True,
        ).stdout
        files = [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]
        if files:
            return files
    except (OSError, subprocess.CalledProcessError):
        pass
    # Не git-репозиторий (или git недоступен) — обходим каталог целиком.
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            full = os.path.join(dirpath, name)
            files.append(os.path.relpath(full, root))
    return files


def lint(root):
    if not os.path.isdir(root):
        print("lint_text: каталог не найден: %s" % root, file=sys.stderr)
        return 2
    in_ci = os.environ.get("GITHUB_ACTIONS") == "true"
    files = sorted(list_files(root))
    problems = 0
    for rel in files:
        full = os.path.join(root, rel)
        if not os.path.isfile(full) or os.path.islink(full):
            continue
        with open(full, "rb") as fh:
            data = fh.read()
        for rule, line, msg in check_content(rel, data):
            problems += 1
            shown = os.path.join(root, rel)
            print("%s:%d: [%s] %s" % (shown, line, rule, msg))
            if in_ci:
                # Аннотация GitHub Actions: находка видна прямо в diff PR.
                # Путь в аннотации должен быть относительно корня репозитория.
                repo_rel = os.path.relpath(os.path.abspath(shown),
                                           os.environ.get("GITHUB_WORKSPACE", os.getcwd()))
                print("::error file=%s,line=%d,title=%s::%s"
                      % (repo_rel, max(line, 1), rule, msg))
    print("lint_text: %s — файлов: %d, находок: %d" % (root, len(files), problems))
    return 1 if problems else 0


def self_test():
    """Каждое правило обязано сработать на своём примере и молчать на чистом тексте."""
    cases = [
        # (описание, путь, байты, ожидаемый набор правил)
        ("чистый файл", "4.grep/base.txt",
         "grep -C 2 \"pattern\" file.txt — контекст\n".encode(), set()),
        ("пустой файл", "8.cp-and-mv/source.txt", b"", set()),
        ("тире и дефис в словах", "x/base.txt",
         "Linux — это система; кто-то пишет UTF-8, Ctrl+R и ls -la\n".encode(), set()),
        ("CRLF", "4.grep/system.log", b"[INFO] ok.\r\n[ERROR] fail.\r\n", {"crlf"}),
        ("нет \\n в конце", "4.grep/file.txt", b"line1\nline2", {"eof-newline"}),
        ("не UTF-8", "x/cp1251.txt", "Привет\n".encode("cp1251"), {"utf8"}),
        ("кириллица в имени каталога", "19.сut-and-paste/base.txt", b"cut -d, -f1\n",
         {"path-ascii"}),
        ("кириллическая С в флаге", "4.grep/base.txt",
         "grep -С 2 \"pattern\" file.txt\n".encode(), {"cyr-flag"}),
        ("кириллическая е в команде", "x/base.txt",
         "grеp -i error system.log\n".encode(), {"mixed-script"}),
    ]
    failed = 0
    for title, path, data, expected in cases:
        got = {rule for rule, _line, _msg in check_content(path, data)}
        ok = got == expected
        failed += not ok
        print("%s %-28s ждали %-18s получили %s"
              % ("ok  " if ok else "FAIL", title, sorted(expected) or "[]", sorted(got) or "[]"))
    print("self-test: %d из %d" % (len(cases) - failed, len(cases)))
    return 1 if failed else 0


USAGE = """usage: lint_text.py DIR [DIR...]   проверить каталоги
       lint_text.py --self-test      проверить, что каждое правило ловит свой дефект"""


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if not argv or any(arg.startswith("-") for arg in argv):
        print(USAGE, file=sys.stderr)
        return 2
    return max(lint(root) for root in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
