# Homelab DevOps Engineer — Блок 1: Фундамент

**Дата начала:** 2026-09-30
**Дата завершения Блока 1:** 2026-10-06
**Автор:** admin@vm-ctrl
**Цель:** построить с нуля инфраструктуру из 5 VM, настроить сеть, DNS, VPN, веб-сервер, автоматизацию и мониторинг.

---

## Содержание

1. [Что построено (итог)](#что-построено)
2. [Хронология: что делали по шагам](#хронология)
3. [Секреты: что это, зачем, как хранятся](#секреты)
4. [Полный список проблем и решений](#проблемы)
5. [Скрипты автоматизации](#скрипты)
6. [Cron — расписание](#cron)
7. [Git — что и куда коммитим](#git)
8. [Что осталось на будущее](#осталось)

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
5. **fail2ban, auditd, unattended-upgrades**.
6. **/etc/hosts** — добавить `127.0.1.1 <hostname>`.

### День 3-4. Сервисы

- **vm-web:** Nginx с двумя сайтами (`site1.local`, `site2.local`) + reverse-proxy на Python (`python3 -m http.server 9000`).
- **vm-dns:** Pi-hole + systemd-resolved отключён + upstream = Cloudflare.
- **vm-vpn:** WireGuard сервер + NAT + IP forwarding.
- **vm-legacy:** Nginx + SELinux Enforcing + firewalld.

### День 5-6. Секреты и автоматизация

- **SSH-ключи** между vm-ctrl и остальными VM.
- **NOPASSWD sudo** на каждой VM (для скриптов).
- **4 скрипта** на vm-ctrl.
- **cron** — расписание.
- **Git** — сохранение всего.

---

## Секреты: что это, зачем, как хранятся

**Секрет** — это данные, которые дают доступ к системе или расшифровке. Если они попадут не к тому — беда.

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

**Что НЕ делать:**
- Не показывать `cat` целиком `/etc/wireguard/` — там приватные ключи.
- Не публиковать в чат.
- Не копировать на чужие машины.

**Грабли, которые прошёл:** выложил `cat *` из `/etc/wireguard/` в чат. Приватные ключи засветились. В учебной лабе не критично, в проде — пересоздавать.

### 3. Sudoers NOPASSWD

**Что это:** файл `/etc/sudoers.d/ansible` содержит правило:

```
admin ALL=(ALL) NOPASSWD: ALL
```

**Что значит:** пользователь `admin` может выполнять любые команды от любого пользователя (включая root), **без пароля**.

**Зачем:** скрипты на vm-ctrl заходят по SSH на другие VM и выполняют `sudo`. Без NOPASSWD — sudo требует пароль через TTY, которого в SSH-сессии нет.

**Что важно понять:** это тоже «секрет» в смысле **привилегии**. Файл должен быть:
- Владелец — root.
- Права — 440.
- Не world-writable.

**Безопасность:** в проде NOPASSWD: ALL — плохо. Правильно — whitelist конкретных команд:
```
admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar
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

**Урок:** для Rocky/Alma/Fedora автоматическая установка часто ломается. Снимать галочку.

### Проблема 2. `sudo: unable to resolve host <name>`

**Симптом:**
```
sudo: unable to resolve host vm-ctrl: Name or service not known
```

**Причина:** `/etc/hosts` пустой или без записи `<hostname>`.

**Почему это происходит:** sudo пытается найти свой hostname для логирования, а DNS не работает (потому что его нет). `/etc/hosts` должен содержать имя хоста — это «последняя миля» резолвинга.

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

**Причина:** файл `~/.ssh/authorized_keys` принадлежал **root**, а не пользователю. SSH отказывается читать файлы, которые принадлежат не тому, кому он их «предназначил».

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

**Причина:** `~/.ssh/known_hosts` не содержит хост-ключ целевой VM. SSH отказывается подключаться к «неизвестной» машине.

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

**Решение:** NOPASSWD sudo.

Файл `/etc/sudoers.d/ansible`:
```
admin ALL=(ALL) NOPASSWD: ALL
```

**Урок:** это **стандарт для автоматизации**. Ansible работает так же.

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

**Причина:** правило `iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE` — **без указания источника**. Маскарадится **весь** исходящий трафик через `enp0s3`, включая пинги к соседям. Обратный маршрут ломается.

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

**Причина:** cron запускает задачу от `admin`, а в `/var/log/` писать может только root. `>>` работает **от текущего пользователя**, поэтому падает с `Permission denied`.

**Решение:** логи **в домашнюю папку**:
```
*/15 * * * * /home/admin/scripts/check_services.sh >> /home/admin/logs/check_services.log 2>&1
```

### Проблема 16. lynis: `command -v` пусто через sudo

**Симптом:** `ssh user@host "sudo command -v lynis"` — пусто, хотя lynis установлен.

**Причина:** `command` — это **shell builtin** (встроенная команда bash), а `sudo` не умеет вызывать builtins.

**Решение:**
```bash
ssh user@host "sudo sh -c 'command -v lynis >/dev/null'"
```
`sh -c '...'` запускает **новый shell** под sudo, и `command` работает.

### Проблема 17. lynis на Rocky: пустой отчёт

**Симптом:** lynis на Rocky создаёт файл 0 байт.

**Причина:** флаг `--quiet` в новых версиях lynis подавляет **весь** вывод, включая нужный.

**Решение:** заменить `--quick --quiet` на `--quick --no-colors`.

### Проблема 18. lynis: PID-файл остаётся от прерванного запуска

**Симптом:**
```
Warning: PID file exists, probably another Lynis process is running.
```

**Причина:** предыдущий запуск был прерван (Ctrl+C), PID-файл не удалился.

**Решение:**
```bash
ssh user@host "sudo rm -f /var/run/lynis.pid /tmp/lynis.pid"
```

---

## Скрипты автоматизации

Все скрипты в `/home/admin/scripts/` на vm-ctrl. Запускаются через cron.

### 1. `check_services.sh`

**Что:** проверяет ключевые сервисы на всех VM.
**Когда:** каждые 15 минут.
**Куда:** `~/logs/check_services.log` + syslog при падении.

Проверяет:
- vm-web: `nginx`, `pyserver`
- vm-dns: `pihole-FTL`
- vm-vpn: `wg-quick@wg0`
- vm-legacy: `nginx`

### 2. `backup_nginx.sh`

**Что:** забирает `/etc/nginx` с vm-web, пакует в архив.
**Когда:** раз в день в 03:00.
**Куда:** `/backup/nginx/`. Хранит 7 последних.

**Предварительный шаг:** `setfacl` на vm-web, чтобы admin читал `/etc/nginx`.

### 3. `disk_report.sh`

**Что:** собирает `df -h` и `du -sh /var/log` со всех VM.
**Когда:** каждый час.
**Куда:** `/var/log/disk_report.log` (или `~/logs/`).

### 4. `security_audit.sh`

**Что:** запускает `lynis audit system` на всех VM.
**Когда:** воскресенье в 04:00.
**Куда:** `/var/log/lynis/<vm>-YYYY-MM-DD.log`.

---

## Cron

**Что такое cron:** демон, который запускает команды по расписанию. Каждый пользователь имеет свой `crontab`.

**Формат:**
```
минута  час  день_месяца  месяц  день_недели   команда
```

**Наш crontab:**

```cron
*/15 * * * * /home/admin/scripts/check_services.sh >> /home/admin/logs/check_services.log 2>&1
0 * * * * /home/admin/scripts/disk_report.sh >> /home/admin/logs/disk_report.log 2>&1
0 3 * * * /home/admin/scripts/backup_nginx.sh >> /home/admin/logs/backup_nginx.log 2>&1
0 4 * * 0 /home/admin/scripts/security_audit.sh >> /home/admin/logs/security_audit.log 2>&1
```

**Что значит `>> ... 2>&1`:** весь stdout и stderr **дописывать в файл**. Без этого cron пытается послать ошибки по email (что на домашнем сервере не работает).

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
├── diary-2026-10-06-scripts.md
├── scripts/
│   ├── check_services.sh
│   ├── backup_nginx.sh
│   ├── disk_report.sh
│   └── security_audit.sh
└── .gitignore
```

**`.gitignore`:**
```
*.retry
.env
*.key
*.pem
id_*
known_hosts
.terraform/
*.tfstate*
kubeconfig
*.log
__pycache__/
```

**Команды:**
```bash
cd ~/home_lab
git add .
git commit -m "..."
git push
```

---

## Что осталось

- [ ] Закоммитить всё в Git и запушить на GitHub.
- [ ] Проверить, что cron пишет логи (через 15 минут).
- [ ] Сделать снапшоты VM в VirtualBox (страховка перед Блоком 2).
- [ ] Начать Блок 2 (Ansible).

---

**Конец README.**
