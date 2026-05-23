# 11 · Git workflow (PR, review, роли)

> Тема из вакансии: «Git (PR, review, работа с ролями)».

## Цель и навыки

Не «выучить git-команды», а понять **рабочий процесс команды**: feature-branch → PR → review → squash-merge. С практикой на Ansible-роли, потому что именно так выглядит дневная работа DevOps-инженера в этой вакансии.

После лабы ты:

- понимаешь **3 состояния файла** (working tree / index / HEAD) и какие команды между ними двигают изменения;
- работаешь по feature-branch flow: ветка от `main` → коммиты → PR → review → squash & merge → удаление ветки;
- умеешь **резолвить merge-конфликт** в YAML и не паниковать;
- пишешь осмысленные коммит-сообщения (Conventional Commits как минимум);
- знаешь про `git rebase -i` для подчистки коммитов **до** push, но не после;
- умеешь читать review: смотришь diff построчно, оставляешь предметные замечания, а не «мне не нравится».

## Теоретический минимум

**Три состояния**: рабочее дерево → index (staged) → HEAD. Команды:
- `git add`  — working → index
- `git commit` — index → HEAD
- `git reset --soft HEAD~1` — HEAD → index (откатить коммит, оставив изменения)
- `git reset HEAD <file>` — index → working (unstage)

**Граф git** — это DAG коммитов. Ветка — это **метка** на коммите. `merge` создаёт merge-commit с двумя родителями; `rebase` переписывает коммиты так, будто они изначально росли от другой ветки.

**Squash-merge** — все коммиты feature-ветки склеиваются в один при мердже в main. Это то, что чаще всего хотят в GitHub-репах: history main'а остаётся чистой, в feature-ветке можно «лепить» как угодно.

**Rebase vs merge.** До push в общую ветку — `rebase` свободно. После push — `merge` (rebase меняет SHA, и все, кто склонировал, получают конфликт).

**Conventional Commits.** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`. Не догма, но команды любят.

## Базовая отработка

Будем работать в учебном репо на самой VM — это безопасно и наглядно. Для PR можно использовать локальный bare-repo как «remote» или твой GitHub-аккаунт (если есть).

### Шаг 1. Базовая настройка

```bash
git config --global user.name  "Junior DevOps"
git config --global user.email "junior@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase false        # honest merge; для команд иногда true
git config --global core.editor "nano"        # или vim/code
git config --global rerere.enabled true       # помнит решения конфликтов
git config --global push.default simple
git config --global push.autoSetupRemote true
```

### Шаг 2. Локальный «remote» через bare-repo

```bash
mkdir -p ~/git-lab && cd ~/git-lab
git init --bare upstream.git           # «GitHub» в одной папке

git clone ./upstream.git work
cd work
```

Теперь `upstream.git` — это remote, в который мы будем «пушить PR».

### Шаг 3. Положить инициальный код (Ansible-роль)

```bash
mkdir -p roles/common/{tasks,defaults}
cat > roles/common/defaults/main.yml <<'EOF'
common_packages: [curl, jq, htop]
EOF
cat > roles/common/tasks/main.yml <<'EOF'
- name: Install common packages
  ansible.builtin.apt:
    name: "{{ common_packages }}"
    update_cache: yes
EOF
cat > README.md <<'EOF'
# lab-roles
Ansible roles for the screening lab.
EOF

git add .
git commit -m "feat(roles/common): initial role with apt install"
git push -u origin main
git log --oneline --decorate --graph --all
```

### Шаг 4. Feature-branch с осмысленной историей

Добавим в роль: NTP-сервис, и в отдельном коммите — обновление README.

```bash
git switch -c feat/ntp

cat >> roles/common/tasks/main.yml <<'EOF'

- name: Ensure chrony is installed and running
  ansible.builtin.apt:
    name: chrony
    state: present
- name: Enable chrony
  ansible.builtin.systemd:
    name: chrony
    enabled: yes
    state: started
EOF
git add roles/common/tasks/main.yml
git commit -m "feat(roles/common): manage chrony service for NTP"

cat >> README.md <<'EOF'

## Roles
- `common`: apt packages + chrony.
EOF
git add README.md
git commit -m "docs: list common role responsibilities"

git push -u origin feat/ntp
git log --oneline --graph --all
```

### Шаг 5. PR (через `git request-pull`, если нет GitHub)

```bash
git request-pull main origin feat/ntp
```

Эта команда генерит описание PR (что бы ты вставил в GitHub UI). Прочитай вывод — это и есть «PR description» в дёшево-сердито виде.

Если есть GitHub:

```bash
gh pr create --title "feat: chrony in common role" --body "Adds chrony management and docs update."
```

### Шаг 6. «Review» — самокритика своего же PR

`git diff main..feat/ntp` — смотри **построчно**. Спрашивай себя:

- читается ли коммит-сообщение как «что меняем и зачем»?
- нет ли в diff лишних строк (CR/LF, trailing whitespace)?
- идемпотентна ли задача? (`state: present` — да, `apt install -y …` через `shell` — нет.)
- проходит ли `ansible-lint roles/common`?

Поправь, если что — **amend в свой последний коммит, пока не пушнул дальше**:

```bash
echo "" >> roles/common/tasks/main.yml          # допустим, тонкая правка
git add -p                                       # выбери hunks интерактивно
git commit --amend --no-edit
git push --force-with-lease                      # безопасный force на свою ветку
```

> Никогда не делай `git push --force` на чужую/общую ветку. `--force-with-lease` — проверяет, что upstream не сдвинули, и **отказывается** если сдвинули.

### Шаг 7. Merge в main (squash)

```bash
git switch main
git pull
git merge --squash feat/ntp
git commit -m "feat(roles/common): manage chrony for NTP

Adds chrony service install + enable, docs updated.

Closes #1"
git push
git branch -d feat/ntp
git push origin --delete feat/ntp
git log --oneline --graph --all
```

## Расширенная отработка

### Задача 1. Конфликт в YAML

Открой две ветки: `feat/extra-packages` (добавляет `ncdu` в `common_packages`) и `feat/security-packages` (добавляет `ufw` в **тот же список**). Помержи одну, попробуй мержить вторую — будет конфликт. Резолви руками так, чтобы оба пакета оказались в списке:

```yaml
common_packages: [curl, jq, htop, ncdu, ufw]
```

Проверь, что `ansible-playbook --syntax-check` чистый, закоммить `merge conflict resolved` (можно `git commit` без -m — он откроет редактор с подготовленным сообщением).

### Задача 2. `rebase -i` для подчистки

В новой ветке сделай 3 «грязных» коммита (`wip`, `fix typo`, `oops`). До push'а:

```bash
git rebase -i HEAD~3
# в редакторе: pick → squash, поправь сообщение
git push
```

После push в общую — **не делай так**. Используй revert + новый коммит.

### Задача 3. .gitignore и не положить лишнего

В корне репы добавь:

```
*.retry
*.swp
.ansible/tmp/
group_vars/*/secrets.yml
*.pem
*.key
```

Затем создай файл `group_vars/all/secrets.yml` с фейковым «паролем» — `git status` не должен его видеть. Это критично для real-life: один забытый `id_rsa` в публичной репе = пол-дня инцидента.

## Acceptance criteria

- [ ] `git log --oneline --graph --all` показывает linear-ish history с осмысленными сообщениями.
- [ ] Все коммиты подписаны в Conventional-Commits-стиле (`type(scope): subject`).
- [ ] Feature-ветка `feat/ntp` смёржена в `main` squash-мерджем и удалена локально + удалённо.
- [ ] `git diff` ни на одном из этапов не показывает CR/LF мусор.
- [ ] (Расширенная) конфликт в YAML резолвится корректно (`ansible-playbook --syntax-check` проходит).

## Что обсудить на ревью

1. Чем squash-merge отличается от обычного merge-commit? Когда что хочешь?
2. Что произойдёт, если ты `git push --force` в `main`? Как от этого защитить репу? (Подсказка: branch protection rules.)
3. Что такое `git reflog` и почему он спасает после «я случайно `reset --hard`»?
4. Что делает `git bisect`?
5. Когда `git rebase` лучше `merge`, и наоборот?
6. Что такое «detached HEAD» и как из него выйти без потерь?

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `! [rejected]` при push | upstream сдвинулся | `git pull --rebase` (на своей ветке) |
| `Updates were rejected because the tip of your current branch is behind` | то же | как выше |
| Случайно закоммитил `.env` | нет gitignore | `git rm --cached .env`, добавить в `.gitignore`, **сменить компрометированные секреты** |
| `git rebase` падает с конфликтами один за другим | большой rebase | пересмотри стратегию: маленькие коммиты, частый merge с main |
| `merge: refusing to merge unrelated histories` | репы стартовали независимо | `git pull --allow-unrelated-histories` (понимай зачем) |
