# Homelab DevOps Engineer — Блок 1: Фундамент

**Дата начала:** 2026-09-30
**Дата завершения Блока 1:** 2026-10-06
**Автор:** admin@vm-ctrl
**Цель:** собрать с нуля домашнюю инфраструктуру из 5 виртуалок. Сеть, DNS, VPN, веб-сервер, автоматизация, мониторинг. Всё руками, чтобы понять, как оно работает под капотом.

**Связанный проект:** [ansible-homelab-project](https://github.com/al-kv/ansible-homelab-project). Та же инфраструктура, но развёрнутая через Ansible. Здесь я собирал всё руками, там автоматизировал.

---

## Содержание

1. [Что построено (итог)](#что-построено)
2. [Хронология: что делали по шагам](#хронология)
3. [Секреты: что это, зачем, как хранятся](#секреты)
4. [Полный список проблем и решений](#проблемы)
5. [Скрипты автоматизации](#скрипты)
6. [Cron — расписание](#cron)
7. [Git — что и куда коммитим](#git)
8. [SELinux на vm-legacy](#selinux)
9. [Отступления от ТЗ](#отступления)
10. [Доказательства работы VPN](#vpn-proof)
11. [Что осталось на будущее](#осталось)

---

## Что построено

### 5 виртуальных машин (VirtualBox, Bridged Adapter)

| # | Имя | ОС | IP | Пользователь | Роль |
|---|---|---|---|---|---|
| 1 | vm-ctrl | Ubuntu 24.04 | 192.168.1.131 | admin | Мозг. Ansible, скрипты, cron |
| 2 | vm-web | Ubuntu 24.04 | 192.168.1.82 | admin | Nginx: 2 сайта + reverse-proxy на Python |
| 3 | vm-dns | Ubuntu 24.04 | 192.168.1.94 | admin | Pi-hole: DNS + блокировка рекламы |
| 4 | vm-vpn | Debian 13 | 192.168.1.77 | admin1 | WireGuard VPN сервер |
| 5 | vm-legacy | Rocky Linux 9.8 | 192.168.1.62 | student | RHEL-мир, SELinux, firewalld |

**Сеть:** одна подсеть `192.168.1.0/24`, шлюз `192.168.1.1`.

**DNS:** все VM ходят за DNS на `192.168.1.94` (Pi-hole).

**Firewall:**
- Ubuntu/Debian — `ufw`
- Rocky — `firewalld`
- Открыто только нужное.

**SSH:** вход только по ключу ed25519, пароли отключены, root-логин запрещён.

**Автоматизация:** 4 bash-скрипта на vm-ctrl, запускаются через cron. Всё в Git.

---

## Хронология: что делали по шагам

### День 1-2. Установка 5 VM

- VirtualBox, Bridged Adapter.
- Ubuntu Server 24.04, Debian 13, Rocky 9.8 — Minimal Install.
- Пользователи: `admin` (Ubuntu/Debian), `admin1` (Debian-vpn), `student` (Rocky).

### День 2-3. Базовая настройка каждой VM (руками)

Для каждой VM:
1. **Static IP** (netplan / nmcli).
2. **DNS → Pi-hole** (`/etc/resolv.conf` или nmcli).
3. **SSH hardening** (drop-in `99-hardening.conf`).
4. **Firewall** (ufw / firewalld).
5. **fail2ban, auditd, unattended-upgrades** (на Rocky — `dnf-automatic`).
6. **/etc/hosts** — добавить `127.0.1.1 <hostname>` и имена всех 5 VM.

### День 3-4. Сервисы

- **vm-web:** Nginx с двумя сайтами (`site1.local`, `site2.local`) + reverse-proxy на Python (`python3 -m http.server 9000` через systemd-юнит `pyserver.service`, см. `configs/systemd/`).
- **vm-dns:** Pi-hole + systemd-resolved отключён + upstream = Cloudflare.
- **vm-vpn:** WireGuard сервер + NAT + IP forwarding.
- **vm-legacy:** Nginx + SELinux Enforcing + firewalld (для reverse-proxy нужен `setsebool -P httpd_can_network_connect on`).

### День 5-6. Секреты и автоматизация

- **SSH-ключи** между vm-ctrl и остальными VM.
- **NOPASSWD sudo** на каждой VM (для скриптов).
- **4 скрипта** на vm-ctrl.
- **cron** — расписание.
- **Git** — сохранение всего.

---

## Секреты: что это, зачем, как хранятся

**Секрет** это то, что даёт доступ к системе: пароль, ключ, токен. Если он утечёт не к тому человеку, будет плохо. Поэтому важно понимать, что это за секрет, где он лежит и кому доступен.

### 1. SSH-ключи (приватный + публичный)

**Что это:**
- **Приватный ключ** (`~/.ssh/id_ed25519`) — ЭЦП, которой ты доказываешь, что ты — это ты.
- **Публичный ключ** (`~/.ssh/id_ed25519.pub`) — «отпечаток» приватного. Раздаётся всем, кому хочешь разрешить вход.

**Как работает:**
1. Сервер имеет список разрешённых публичных ключей (`~/.ssh/authorized_keys`).
2. Клиент подключается, отправляет свой публичный ключ.
3. Сервер проверяет, есть ли такой в списке.
4. Если есть — клиент доказывает, что у него есть приватный ключ (через криптографию).
5. Пароль не нужен.

**Что хранится где:**

| Файл | Где | Кому можно |
|---|---|---|
| `id_ed25519` (приватный) | только vm-ctrl | никому |
| `id_ed25519.pub` (публичный) | везде | всем |
| `authorized_keys` (список публичных) | на каждой VM | содержит публичные ключи |

**Правило:** приватный ключ **никогда** не копируется никуда. Публичный — можно показывать всем.

**Права на файлы (критично):**
- `~/.ssh` — `700`, владелец — сам пользователь.
- `~/.ssh/authorized_keys` — `600`, владелец — сам пользователь.
- `~/.ssh/id_ed25519` — `600`, владелец — сам пользователь.

**Как мы это использовали:**
- Одна пара ключей на vm-ctrl.
- Публичный ключ добавлен в `authorized_keys` на 4 VM.
- Теперь vm-ctrl может ходить на остальные без пароля.

### 2. WireGuard-ключи (приватный + публичный)

**Аналогично SSH**, но для VPN.

- Приватный ключ **сервера** — только на vm-vpn.
- Приватный ключ **клиента** (Windows) — только на Windows.
- Публичные — обменяны между сторонами.

**Правило:**
- В конфиге сервера: `[Interface] PrivateKey = server_private` + `[Peer] PublicKey = client_public`.
- В конфиге клиента: `[Interface] PrivateKey = client_private` + `[Peer] PublicKey = server_public`.

**Права на файлы:**
- `/etc/wireguard/` — `700`, владелец root.
- `/etc/wireguard/wg0.conf` — `600`, владелец root.

**Что НЕ делать:**
- Не показывать `cat` целиком `/etc/wireguard/` — там приватные ключи.
- Не публиковать в чат.
- Не копировать на чужие машины.

**Грабли, которые прошёл:** выложил `cat *` из `/etc/wireguard/` в чат. Приватные ключи засветились. В учебной лабе не критично, в проде — пересоздавать.

В репозитории лежат шаблоны `configs/wireguard/wg0.server.conf` и `wg0.client.conf` **с замазанными `<REDACTED>` ключами** — для документации.

### 3. Sudoers NOPASSWD

**Что это:** файл `/etc/sudoers.d/ansible` содержит правило NOPASSWD для пользователя.

**Что значит:** пользователь может выполнять команды от root **без пароля**.

**Зачем:** скрипты на vm-ctrl заходят по SSH на другие VM и выполняют `sudo`. Без NOPASSWD — sudo требует пароль через TTY, которого в SSH-сессии нет.

**Что важно понять:** это тоже «секрет» в смысле **привилегии**. Файл должен быть:
- Владелец — root.
- Права — 440.
- Не world-writable.

**Правила по VM:**

| VM | Пользователь | Правило |
|---|---|---|
| vm-ctrl | admin | `admin ALL=(ALL) NOPASSWD: ALL` |
| vm-web | admin | `admin ALL=(ALL) NOPASSWD: ALL` |
| vm-dns | admin | `admin ALL=(ALL) NOPASSWD: ALL` |
| vm-vpn | admin1 | `admin1 ALL=(ALL) NOPASSWD: ALL` |
| vm-legacy | student | `student ALL=(ALL) NOPASSWD: ALL` |

**Безопасность:** в проде `NOPASSWD: ALL` — плохо. Правильно — whitelist конкретных команд:

```
admin   ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar, /usr/bin/tee
admin1  ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/wg
student ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/lynis
```

### 4. Пароль Pi-hole

- Хранится в `/etc/pihole/pihole.toml` на vm-dns.
- Доступен только root.
- Задаётся командой `pihole -a -p`.
- Используется только для админки (`http://192.168.1.94/admin`).

### 5. Пароли пользователей

- `admin`, `admin1`, `student` — есть пароли для первого входа.
- Используются для локального входа (через консоль VirtualBox) и для первого добавления SSH-ключа.
- После настройки ключей и NOPASSWD — пароли почти не нужны.

### Что НЕ является секретом

- IP-адреса VM.
- Имена пользователей.
- Публичные ключи SSH.
- Публичные ключи WireGuard.
- Конфиги (кроме тех, что содержат приватные ключи).

---

## Полный список проблем и решений

### Проблема 1. `Image checksum error` при загрузке ISO

**Симптом:** при запуске VM с ISO — «ISOLINUX: Image checksum error».

**Причина:** VirtualBox подсовывал свой файл `Unattended-*.viso` вместо реального ISO. Это происходит, когда при создании VM включена галочка «Unattended Installation».

**Решение:**
- Удалить все `Unattended-*.viso` из настроек носителей.
- Подключить ISO **вручную** через `Настройки → Носители → Добавить оптический привод`.
- При создании VM — **галочку «Skip Unattended Installation» ПОСТАВИТЬ**.

**Урок:** на Rocky, Alma и Fedora автоустановка через VirtualBox часто ломается. Проще сразу снять галочку и подключить ISO руками.

### Проблема 2. `sudo: unable to resolve host <name>`

**Симптом:**
```
sudo: unable to resolve host vm-ctrl: Name or service not known
```

**Причина:** `/etc/hosts` пустой или без записи `<hostname>`.

**Решение:** добавить в `/etc/hosts`:
```
127.0.0.1       localhost localhost.localdomain
127.0.1.1       vm-ctrl
::1             localhost localhost.localdomain
```

Строка **`127.0.1.1 <hostname>`** — ключевая.

### Проблема 3. netplan: `malformed address`

**Симптом:**
```
Error in network definition: malformed address '192.168.1./24'
```

**Причина:** опечатка в IP — пропущен последний октет.

**Решение:** писать полный IP `192.168.1.131/24`.

**Урок:** netplan **очень чувствителен к синтаксису**. YAML не прощает пробелов/опечаток.

### Проблема 4. `ufw enable` прерывается с `Aborted`

**Симптом:**
```
Command may disrupt existing ssh connections. Proceed with operation (y|n)? sudo chattr ...
Aborted
```

**Причина:** в ответ на вопрос «продолжить?» была введена **другая команда**, а не `y`.

**Решение:** ответить строго `y` + Enter.

**Урок:** ufw всегда предупреждает, что может оборвать SSH. Но если `22/tcp` уже разрешён — не оборвёт.

### Проблема 5. Pi-hole: `dns.upstreams = []` → все dig возвращают REFUSED

**Симптом:** после установки Pi-hole команда `dig ya.ru` возвращает `REFUSED`.

**Причина:** при установке Pi-hole не прописал upstream DNS. Значит Pi-hole принимает запросы, но **не знает, куда их передавать** и отвечает отказом.

**Решение:**
```bash
sudo pihole-FTL --config dns.upstreams '["1.1.1.1", "8.8.8.8"]'
sudo systemctl restart pihole-FTL
```

**Урок:** после установки Pi-hole всегда проверять:
```bash
sudo pihole-FTL --config dns.upstreams
```
Если `[]` — задать вручную.

### Проблема 6. Debian: `nmcli: unknown connection 'enp0s3'`

**Симптом:** при попытке настроить static IP на Debian:
```
Error: unknown connection 'enp0s3'.
```

**Причина:** на Debian NetworkManager **не всегда** называет соединение именем интерфейса. У нас оно называлось `"Wired connection 1"` (с пробелами!).

**Решение:**
```bash
sudo nmcli connection show
```
Увидеть реальное имя → использовать в кавычках:
```bash
sudo nmcli connection modify "Wired connection 1" ...
```

**Урок:** **сначала** `nmcli connection show`, потом менять. На каждом дистрибутиве имя может отличаться.

### Проблема 7. `Server refused our key` при SSH

**Симптом:** при подключении через MobaXterm по ключу — `Server refused our key`.

**Причина:** файл `~/.ssh/authorized_keys` принадлежал **root**, а не пользователю.

**Решение:**
```bash
sudo chown -R admin1:admin1 ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

**Урок:** права на `.ssh` — **критичны**. SSH игнорирует файлы, которые:
- Принадлежат не тому пользователю.
- Имеют права шире, чем `700` / `600`.
- World-writable.

### Проблема 8. `Host key verification failed`

**Симптом:** с vm-ctrl при попытке `ssh admin@192.168.1.82` — `Host key verification failed`.

**Причина:** `~/.ssh/known_hosts` не содержит хост-ключ целевой VM.

**Решение:** первый коннект с:
```bash
ssh -o StrictHostKeyChecking=accept-new admin@192.168.1.82 hostname
```

**Урок:** `accept-new` — идеально для скриптов. Принимает новые хосты, но предупреждает, если ключ изменился.

### Проблема 9. `sudo: a terminal is required to read the password`

**Симптом:** скрипт по SSH:
```
sudo: a terminal is required to read the password
sudo: a password is required
```

**Причина:** SSH-сессия **не имеет TTY**, а sudo по умолчанию требует пароль **через TTY**.

**Решение:** NOPASSWD sudo (см. раздел «Секреты»).

**Урок:** без NOPASSWD автоматизация по SSH не работает в принципе. Ansible устроен так же, поэтому в реальных проектах это стандарт.

### Проблема 10. WireGuard: handshake did not complete

**Симптом:** в логе WireGuard на Windows:
```
Handshake for peer 1 (192.168.1.77:51820) did not complete after 5 seconds
```

**Причина:** `AllowedIPs = 10.10.0.0/24, 192.168.1.0/24` в конфиге клиента. Маршрут `192.168.1.0/24` создаётся через туннель — и запрос на `192.168.1.77:51820` тоже пытается уйти **в этот же туннель**, которого ещё нет. Петля.

**Решение:** убрать `192.168.1.0/24` из клиентского `AllowedIPs`:
```
AllowedIPs = 10.10.0.0/24
```

### Проблема 11. WireGuard: SSH к серверу обрывается при рестарте

**Симптом:** `systemctl restart wg-quick@wg0` → SSH-сессия к vm-vpn обрывается.

**Причина:** `AllowedIPs = 10.10.0.2/32, 192.168.1.0/24` в **серверном** конфиге. wg-quick создаёт маршрут `192.168.1.0/24 dev wg0` — весь трафик к домашней сети уходит в туннель, где никого нет.

**Решение:** `AllowedIPs = 10.10.0.2/32` (только VPN-адрес клиента).

**Урок:** **на сервере нельзя указывать локальную сеть в AllowedIPs.** Только VPN-адрес клиента.

### Проблема 12. WireGuard: MASQUERADE без `-s` ломает сеть

**Симптом:** после старта WireGuard пинг до соседней VM падает.

**Причина:** правило `iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE` — **без указания источника**. Маскарадится **весь** исходящий трафик через `enp0s3`, включая пинги к соседям.

**Решение:**
```
iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o enp0s3 -j MASQUERADE
```

`-s 10.10.0.0/24` — маскарад **только для VPN-клиентов**.

### Проблема 13. iptables -t nat -F POSTROUTING обрывает SSH

**Симптом:** после `sudo iptables -t nat -F POSTROUTING` — SSH отвалился.

**Причина:** команда сбрасывает **всю** таблицу NAT. Существующие TCP-сессии теряют состояние трекинга.

**Решение:** не делать на живой системе без нужды. Если делать — в окне **консоли VirtualBox**, а не через SSH.

**Урок:** **отладка сети — только из консоли VirtualBox.** SSH — это твой единственный канал, потеряешь — восстановить сложно.

### Проблема 14. `chmod: Operation not permitted` на скриптах

**Симптом:** `chmod +x check_services.sh` → `Operation not permitted`.

**Причина:** файлы созданы через `sudo vi`, владелец — `root`.

**Решение:**
```bash
sudo chown admin:admin ~/scripts/*.sh
chmod +x ~/scripts/*.sh
```

**Урок:** **не создавай свои файлы через `sudo vi`.** Если очень нужно — потом верни владельца себе.

### Проблема 15. cron: логи не пишутся в `/var/log/`

**Симптом:** после настройки cron файл `/var/log/check_services.log` не создаётся.

**Причина:** cron запускает задачу от `admin`, а в `/var/log/` писать может только root.

**Решение:** логи **в домашнюю папку**:
```
*/15 * * * * /home/admin/scripts/check_services.sh >> /home/admin/logs/check_services.log 2>&1
```

`disk_report.sh` пишет в `/var/log/disk_report.log` (по ТЗ) — файл создан с владельцем `admin`, поэтому пишется без sudo.

### Проблема 16. lynis: `command -v` пусто через sudo

**Симптом:** `ssh user@host "sudo command -v lynis"` — пусто, хотя lynis установлен.

**Причина:** `command` — это **shell builtin** (встроенная команда bash), а `sudo` не умеет вызывать builtins.

**Решение:**
```bash
ssh user@host "sudo sh -c 'command -v lynis >/dev/null'"
```

### Проблема 17. lynis на Rocky: пустой отчёт

**Симптом:** lynis на Rocky создаёт файл 0 байт.

**Причина:** флаг `--quiet` в новых версиях lynis подавляет **весь** вывод.

**Решение:** заменить `--quick --quiet` на `--quick --no-colors`.

### Проблема 18. lynis: PID-файл остаётся от прерванного запуска

**Симптом:**
```
Warning: PID file exists, probably another Lynis process is running.
```

**Причина:** предыдущий запуск был прерван (Ctrl+C), PID-файл не удалился.

**Решение (уже встроено в `security_audit.sh`):**
```bash
ssh user@host "sudo rm -f /var/run/lynis.pid /tmp/lynis.pid"
```

---

## Скрипты автоматизации

Все скрипты в `/home/admin/scripts/` на vm-ctrl. Запускаются через cron.

### 1. `check_services.sh`

**Что:** проверяет ключевые сервисы на всех VM. Различает «хост недоступен» и «сервис упал».
**Когда:** каждые 15 минут.
**Куда:** `~/logs/check_services.log` + syslog при падении.

Проверяет:
- vm-web: `nginx`, `pyserver`
- vm-dns: `pihole-FTL`
- vm-vpn: `wg-quick@wg0`
- vm-legacy: `nginx`

### 2. `backup_nginx.sh`

**Что:** забирает `/etc/nginx` с vm-web по SSH, пакует в архив, проверяет целостность (`stat` + `tar -tzf`), удаляет битые и пустые.
**Когда:** раз в день в 03:00.
**Куда:** `/backup/nginx/`. Хранит 7 последних.

**Предварительный шаг (один раз):** `ssh admin@192.168.1.82 "sudo setfacl -R -m u:admin:rx /etc/nginx"` — чтобы admin мог читать конфиг без sudo.

### 3. `disk_report.sh`

**Что:** собирает `df -h` и `du -sh /var/log` со всех VM.
**Когда:** каждый час.
**Куда:** `/var/log/disk_report.log` (файл создан с владельцем `admin`, пишется без sudo).

### 4. `security_audit.sh`

**Что:** запускает `lynis audit system` на всех VM. Правильно отличает rc=1/2 (lynis нашёл проблемы, но это норма) от rc>2 или 255 (реальная ошибка SSH/sudo).
**Когда:** воскресенье в 04:00.
**Куда:** `/var/log/lynis/<vm>-YYYY-MM-DD.log`.

---

## Cron

**Формат:**
```
минута  час  день_месяца  месяц  день_недели   команда
```

**Наш crontab:**

```cron
*/15 * * * * /home/admin/scripts/check_services.sh  >> /home/admin/logs/check_services.log 2>&1
0    * * * * /home/admin/scripts/disk_report.sh     >  /home/admin/logs/disk_report.cron.log 2>&1
0    3 * * * /home/admin/scripts/backup_nginx.sh    >> /home/admin/logs/backup_nginx.log 2>&1
0    4 * * 0 /home/admin/scripts/security_audit.sh >> /home/admin/logs/security_audit.log 2>&1
```

Скрипты разнесены по времени, чтобы не стартовали одновременно: `disk_report` в `:00`, `backup` в 03:00, `audit` в 04:00 воскресенья. `check_services` — каждые 15 минут.

`disk_report.sh` использует `>` (перезапись) для `.cron.log` — чтобы не путать вывод cron с самим отчётом, который пишется в `/var/log/disk_report.log`.

**Проверка:**
```bash
crontab -l
sudo systemctl status cron
cat ~/logs/check_services.log
```

---

## Git

**Зачем:**
- История версий.
- Резервная копия на GitHub.
- Портфолио.

**Структура репозитория:**

```
~/home_lab/
├── README.md
├── .gitignore
├── LICENSE
├── configs/
│   ├── ssh/99-hardening.conf
│   ├── netplan/50-static-vm-ctrl.yaml
│   ├── ufw/rules-vm-web.txt
│   ├── firewalld/rules-vm-legacy.txt
│   ├── wireguard/wg0.server.conf      # ключи = <REDACTED>
│   ├── wireguard/wg0.client.conf      # ключи = <REDACTED>
│   └── systemd/pyserver.service
└── scripts/
    ├── check_services.sh
    ├── backup_nginx.sh
    ├── disk_report.sh
    └── security_audit.sh
```

**`.gitignore`:**

```
# секреты
.env
*.key
*.pem
id_*
known_hosts
kubeconfig

# terraform
.terraform/
*.tfstate*
*.retry

# артефакты и логи
*.log
logs/
backups/
*.tar.gz
__pycache__/

# мусор
.DS_Store
*.swp
*~
.idea/
.vscode/
```

**Команды:**
```bash
cd ~/home_lab
git add .
git commit -m "..."
git push
```

**Проверка перед коммитом (важно):**
```bash
git status
# убедиться, что в списке НЕТ id_*, *.key, *.pem, *.tar.gz
```

**Удалённый репозиторий:**
- URL: git@github.com:al-kv/Homelab-DevOps-Engineer.git
- Ветка: main

**Если push rejected (non-fast-forward):**
```bash
git pull --rebase origin main
git push -u origin main
```

---

<a id="selinux"></a>
## SELinux на vm-legacy: что чинили и почему

`getenforce` → `Enforcing`. Nginx запустился, но статическая страница не отдавалась (`curl http://192.168.1.62/` → 403). Причина: SELinux по умолчанию запрещает процессу `httpd_t` инициировать сетевые соединения. Nginx у нас работает как reverse-proxy (ходит на `127.0.0.1:9000`), поэтому нужно было разрешить:

```bash
sudo setsebool -P httpd_can_network_connect on
```

`-P` — чтобы флаг сохранился после перезагрузки. После этого страница отдалась.

Для нестандартного порта (например, 8080) дополнительно:

```bash
sudo semanage port -a -t http_port_t -p tcp 8080
```

Проверка: `sudo semanage port -l | grep http_port_t` — 8080 в списке. `policycoreutils-python-utils` установлен (нужен для `semanage`).

---

<a id="отступления"></a>
## Отступления от ТЗ (осознанные)

- **Пользователь `admin`/`admin1`/`student` вместо `ansible`.** Функционально одно и то же: непривилегированный пользователь с NOPASSWD sudo. `AllowUsers` прописан в `configs/ssh/99-hardening.conf` под каждого пользователя.
- **IP-адреса** — реальные из моей лабы (`192.168.1.131`, `.82`, `.94`, `.77`, `.62`), а не `192.168.1.101–105` из ТЗ (в ТЗ указано «пример»).
- **`backup_nginx.sh` → `/backup/nginx/`** (по ТЗ), папка создана с владельцем `admin`, чтобы cron-задача писала без sudo.
- **`disk_report.sh` → `/var/log/disk_report.log`** (по ТЗ), файл создан с владельцем `admin` по той же причине.
- **`security_audit.sh`** различает rc=1/2 (lynis нашёл проблемы — это норма) от rc>2 или 255 (реальная ошибка SSH/sudo). Оригинальный скрипт падал целиком при первом же «замечании» lynis.

---

<a id="vpn-proof"></a>
## Доказательства работы VPN

С Windows-клиента WireGuard после подключения:

```
ping 10.10.0.1     # шлюз wg0 — Windows firewall блокирует ICMP-reply (на функционал не влияет)
ping 192.168.1.94  # vm-dns — OK
```

(`192.168.1.94` — реальный IP vm-dns в моей лабе; в ТЗ указан `.103` как пример.)

Результат `sudo wg show` на vm-vpn:
```
interface: wg0
  listening port: 51820
peer: <CLIENT_PUBLIC_KEY>
  allowed ips: 10.10.0.2/32
```

NAT настроен корректно: `iptables -t nat -L POSTROUTING -n` → `MASQUERADE all -- 10.10.0.0/24 0.0.0.0/0`.

---

<a id="осталось"></a>
## Что осталось на будущее

- [x] Снапшоты всех 5 VM в VirtualBox (перед Блоком 2).
- [x] Скрипты приведены к путям ТЗ (`/backup/nginx`, `/var/log/disk_report.log`).
- [x] `/etc/hosts` с именами всех 5 VM на vm-ctrl.
- [ ] Настроить logrotate для `/var/log/disk_report.log` и `~/logs/*.log` (ротация раз в неделю, 4 архива).
- [ ] Прогнать `shellcheck scripts/*.sh` и зафиксировать вывод в репо.
- [ ] Блок 2 (Ansible) — реализован отдельным репозиторием `ansible-homelab-project`.

---

## Как развернуть у себя (кратко)

Это учебный проект для портфолио, а не готовый инсталлятор. Чтобы повторить у себя, сделай так:

1. Поднять 5 VM (Ubuntu 24.04, Ubuntu 24.04, Ubuntu 24.04, Debian 13, Rocky 9.8),
   Bridged Adapter, статические IP в одной подсети.
2. Заменить IP-адреса в `scripts/*.sh` и `configs/*` на свои.
3. Заменить имена пользователей (`admin`, `admin1`, `student`) на свои
   в скриптах и в `configs/ssh/99-hardening.conf`.
4. Настроить SSH-ключи: с vm-ctrl сгенерировать `ssh-keygen -t ed25519`,
   публичный ключ положить в `authorized_keys` на 4 остальных VM.
5. Установить пакеты по списку из ТЗ Блока 1 (см. выше).
6. Скопировать `configs/*` на соответствующие VM, применить (netplan apply, ufw enable и т.д.).
7. Заполнить свои значения в `configs/wireguard/*.conf` (ключи WireGuard).
8. `crontab -e` на vm-ctrl — вставить 4 строки из раздела «Cron».
9. Проверить: `~/home_lab/scripts/check_services.sh` → все [OK].
**Конец README.**
