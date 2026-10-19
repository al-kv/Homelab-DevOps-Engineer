# Homelab DevOps Engineer - Блок 1

**Дата начала:** 2026-09-30
**Дата завершения:** 2026-10-06
**Автор:** admin@vm-ctrl

## О чём это

Домашняя лаборатория из 5 виртуалок. Собрана руками, без Ansible, чтобы понять, как всё устроено под капотом. Сеть, DNS, VPN, веб-сервер, автоматизация через bash и cron.

**Связанный проект:** [ansible-homelab-project](https://github.com/al-kv/ansible-homelab-project) - та же инфраструктура, но развёрнутая через Ansible. Здесь я собирал всё вручную, там автоматизировал.

---

## Содержание

1. [Что построено](#что-построено)
2. [Хронология](#хронология)
3. [Секреты и как с ними обращаться](#секреты)
4. [18 граблей и как я их обошёл](#проблемы)
5. [Скрипты автоматизации](#скрипты)
6. [Cron](#cron)
7. [Git](#git)
8. [SELinux на Rocky](#selinux)
9. [Отступления от ТЗ](#отступления)
10. [Доказательства работы VPN](#vpn-proof)
11. [Что осталось на будущее](#осталось)
12. [Как развернуть у себя](#развернуть)

---

## Схема сети

    [ Интернет / Шлюз 192.168.1.1 ]
                 |
    ============================================
    |           |            |         |       |
[vm-ctrl]  [vm-web]     [vm-dns]  [vm-vpn]  [vm-legacy]
 .131       .82          .94       .77       .62
 (Admin)    (Nginx)      (DNS)     (VPN)     (Rocky)
    |           |            |         |       |
    +-----------+------------+---------+-------+
                         |
                   [ Windows Клиент ]
                   (через WireGuard 10.10.0.2)

## Что построено

### 5 виртуалок на VirtualBox (Bridged Adapter)

| # | Имя | ОС | IP | Юзер | Роль |
|---|---|---|---|---|---|
| 1 | vm-ctrl | Ubuntu 24.04 | 192.168.1.131 | admin | Контроллер: скрипты, cron, Ansible |
| 2 | vm-web | Ubuntu 24.04 | 192.168.1.82 | admin | Nginx: 2 сайта + reverse-proxy на Python |
| 3 | vm-dns | Ubuntu 24.04 | 192.168.1.94 | admin | Pi-hole: DNS + блокировка рекламы |
| 4 | vm-vpn | Debian 13 | 192.168.1.77 | admin1 | WireGuard VPN сервер |
| 5 | vm-legacy | Rocky 9.8 | 192.168.1.62 | student | RHEL-мир, SELinux, firewalld |

**Сеть:** одна подсеть 192.168.1.0/24, шлюз 192.168.1.1.

**DNS:** все ходят на 192.168.1.94 (Pi-hole).

**Firewall:** на Ubuntu/Debian ufw, на Rocky firewalld. Открыто только нужное.

**SSH:** только по ключу ed25519. Пароли отключены, root-логин запрещён.

**Автоматизация:** 4 bash-скрипта на vm-ctrl, запускаются через cron. Всё лежит в этом репозитории.

---

## Хронология

### Дни 1-2. Установка VM

VirtualBox, Bridged Adapter. Ubuntu 24.04, Debian 13, Rocky 9.8, везде Minimal Install.

Юзеры: admin на Ubuntu/Debian, admin1 на vpn, student на Rocky.

### Дни 2-3. Базовая настройка вручную

Каждая VM:
1. Статический IP (netplan или nmcli).
2. DNS на Pi-hole.
3. SSH hardening через drop-in 99-hardening.conf.
4. Firewall.
5. fail2ban, auditd, unattended-upgrades. На Rocky вместо unattended - dnf-automatic.
6. /etc/hosts: добавить 127.0.1.1 <hostname> и имена всех 5 VM.

### Дни 3-4. Сервисы

- **vm-web:** Nginx с двумя сайтами (site1.local, site2.local). Плюс reverse-proxy на Python через systemd-юнит pyserver.service (см. configs/systemd/).
- **vm-dns:** Pi-hole. systemd-resolved отключён, upstream Cloudflare.
- **vm-vpn:** WireGuard сервер + NAT + IP forwarding.
- **vm-legacy:** Nginx + SELinux Enforcing + firewalld. Для reverse-proxy нужен setsebool -P httpd_can_network_connect on.

### Дни 5-6. Секреты и автоматизация

SSH-ключи между vm-ctrl и остальными. NOPASSWD sudo на каждой VM. 4 скрипта на vm-ctrl. Cron. Всё в Git.

---

## Секреты и как с ними обращаться

Секрет это то, что даёт доступ к системе: пароль, ключ, токен. Если он утечёт не к тому человеку, будет плохо. Поэтому важно понимать, что это за секрет, где он лежит и кому доступен.

### SSH-ключи

Что это:
- **Приватный ключ** (~/.ssh/id_ed25519) - то, чем ты доказываешь, что ты это ты.
- **Публичный ключ** (~/.ssh/id_ed25519.pub) - «отпечаток» приватного. Его можно раздавать всем, кому хочешь разрешить вход.

Как работает вход по ключу:
1. Сервер держит список разрешённых публичных ключей в ~/.ssh/authorized_keys.
2. Клиент подключается и отправляет свой публичный ключ.
3. Сервер смотрит: есть такой в списке или нет.
4. Если есть, клиент доказывает, что у него есть парный приватный ключ.
5. Пароль не нужен.

Что где лежит:

| Файл | Где | Кому можно |
|---|---|---|
| id_ed25519 (приватный) | только vm-ctrl | никому |
| id_ed25519.pub (публичный) | везде | всем |
| authorized_keys | на каждой VM | там только публичные ключи |

**Правило:** приватный ключ никогда никуда не копируется. Публичный можно показывать всем.

**Права (это критично, SSH молча откажется работать при неверных правах):**
- ~/.ssh - 700, владелец сам пользователь.
- ~/.ssh/authorized_keys - 600, владелец сам пользователь.
- ~/.ssh/id_ed25519 - 600, владелец сам пользователь.

**Как я это использовал:** одна пара ключей на vm-ctrl. Публичный добавил в authorized_keys на 4 VM. Теперь vm-ctrl ходит на остальные без пароля.

### WireGuard-ключи

Логика та же, что у SSH, но для VPN. Приватный ключ сервера лежит только на vm-vpn. Приватный ключ клиента (Windows) только на Windows. Публичные обменяны между сторонами.

Правило простое:
- В конфиге сервера: [Interface] PrivateKey = server_private + [Peer] PublicKey = client_public.
- В конфиге клиента: [Interface] PrivateKey = client_private + [Peer] PublicKey = server_public.

Права:
- /etc/wireguard/ - 700, владелец root.
- /etc/wireguard/wg0.conf - 600, владелец root.

Чего не делать:
- Не показывать cat целиком /etc/wireguard/, там приватные ключи.
- Не публиковать в открытый доступ (соцсети, форумы).
- Не копировать на чужие машины.

**Мои грабли:** выложил однажды cat * из /etc/wireguard/ в чат. Приватные ключи засветились. В учебной лабе не критично, в проде пришлось бы всё пересоздавать.

В репозитории лежат шаблоны configs/wireguard/wg0.server.conf и wg0.client.conf с замазанными REDACTED ключами. Только для документации.

### Sudoers NOPASSWD

Файл /etc/sudoers.d/ansible содержит правило NOPASSWD для пользователя. То есть пользователь может выполнять команды от root без пароля.

Зачем это нужно: скрипты на vm-ctrl заходят по SSH на другие VM и выполняют sudo. Без NOPASSWD sudo требует пароль через TTY, которого в SSH-сессии нет. Автоматизация просто не работает.

Это тоже «секрет» в смысле привилегии. Файл должен быть:
- Владелец root.
- Права 440.
- Не world-writable.

Правила по VM:

| VM | Юзер | Правило |
|---|---|---|
| vm-ctrl | admin | admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar, /usr/bin/tee |
| vm-web | admin | admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar, /usr/bin/tee |
| vm-dns | admin | admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar, /usr/bin/tee |
| vm-vpn | admin1 | admin1 ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/wg |
| vm-legacy | student | student ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/lynis |

В проде NOPASSWD: ALL это плохо. Правильно ограничивать конкретными командами:

    admin   ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/tar, /usr/bin/tee
    admin1  ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/wg
    student ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/lynis

### Пароль Pi-hole

Лежит в /etc/pihole/pihole.toml на vm-dns. Доступен только root. Задаётся через pihole -a -p. Нужен только для админки на http://192.168.1.94/admin.

### Пароли пользователей

У admin, admin1, student есть пароли для первого входа. Нужны для консоли VirtualBox и для первого добавления SSH-ключа. После настройки ключей и NOPASSWD почти не используются.

### Что секретом не является

IP-адреса, имена пользователей, публичные ключи SSH и WireGuard, конфиги без приватных ключей.

---

## 18 граблей и как я их обошёл

### 1. Image checksum error при загрузке ISO

**Что вижу:** при запуске VM с ISO падает с «ISOLINUX: Image checksum error».

**Почему:** VirtualBox подсовывал свой Unattended viso вместо реального ISO. Это бывает, когда при создании VM включена галочка «Unattended Installation».

**Что делать:**
- Удалить все Unattended viso из настроек носителей.
- Подключить ISO вручную: Настройки, Носители, Добавить оптический привод.
- При создании VM ставить галочку «Skip Unattended Installation».

**Вывод:** на Rocky, Alma и Fedora автоустановка через VirtualBox часто ломается. Проще сразу снять галочку и подключить ISO руками.

### 2. sudo: unable to resolve host

**Что вижу:**
    sudo: unable to resolve host vm-ctrl: Name or service not known

**Почему:** /etc/hosts пустой или без записи с hostname.

**Что делать:** добавить в /etc/hosts:
    127.0.0.1       localhost localhost.localdomain
    127.0.1.1       vm-ctrl
    ::1             localhost localhost.localdomain

Строка 127.0.1.1 <hostname> тут ключевая.

### 3. netplan: malformed address

**Что вижу:**
    Error in network definition: malformed address '192.168.1./24'

**Почему:** опечатка в IP, пропущен последний октет.

**Что делать:** писать полный IP 192.168.1.131/24.

**Вывод:** netplan очень чувствителен к синтаксису. YAML не прощает пробелов и опечаток.

### 4. ufw enable прерывается с Aborted

**Что вижу:**
    Command may disrupt existing ssh connections. Proceed with operation (y|n)? sudo chattr ...
    Aborted

**Почему:** на вопрос «продолжить?» ввёл другую команду вместо y.

**Что делать:** ответить строго y и Enter.

**Вывод:** ufw всегда предупреждает, что может оборвать SSH. Но если 22/tcp уже разрешён, не оборвёт.

### 5. Pi-hole: все dig возвращают REFUSED

**Что вижу:** после установки Pi-hole dig ya.ru возвращает REFUSED.

**Почему:** при установке не прописал upstream DNS. Pi-hole принимает запросы, но не знает, куда их передавать, и отвечает отказом.

**Что делать:**
    sudo pihole-FTL --config dns.upstreams '["1.1.1.1", "8.8.8.8"]'
    sudo systemctl restart pihole-FTL

**Вывод:** после установки Pi-hole всегда проверять sudo pihole-FTL --config dns.upstreams. Если пусто, задать вручную.

### 6. Debian: nmcli не знает enp0s3

**Что вижу:**
    Error: unknown connection 'enp0s3'.

**Почему:** на Debian NetworkManager не всегда называет соединение именем интерфейса. У меня оно называлось «Wired connection 1», с пробелами.

**Что делать:**
    sudo nmcli connection show

Посмотреть реальное имя и использовать его в кавычках:
    sudo nmcli connection modify "Wired connection 1" ...

**Вывод:** сначала nmcli connection show, потом менять. На каждом дистрибутиве имя может отличаться.

### 7. Server refused our key при SSH

**Что вижу:** при подключении через MobaXterm по ключу Server refused our key.

**Почему:** файл ~/.ssh/authorized_keys принадлежал root, а не пользователю. SSH отказывается читать файлы, которые принадлежат не тому.

**Что делать:**
    sudo chown -R admin1:admin1 ~/.ssh
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

**Вывод:** права на .ssh критичны. SSH молча игнорирует файлы, которые принадлежат не тому пользователю, имеют права шире 700/600, или world-writable.

### 8. Host key verification failed

**Что вижу:** с vm-ctrl при попытке ssh admin@192.168.1.82 падает с Host key verification failed.

**Почему:** ~/.ssh/known_hosts не содержит хост-ключ целевой VM. SSH отказывается идти на «неизвестную» машину.

**Что делать:** первый коннект с флагом:
    ssh -o StrictHostKeyChecking=accept-new admin@192.168.1.82 hostname

**Вывод:** accept-new идеален для скриптов. Принимает новые хосты, но предупреждает, если ключ изменился.

### 9. sudo: a terminal is required

**Что вижу:** скрипт по SSH падает:
    sudo: a terminal is required to read the password
    sudo: a password is required

**Почему:** у SSH-сессии нет TTY, а sudo по умолчанию требует пароль через TTY.

**Что делать:** настроить NOPASSWD sudo (см. раздел «Секреты»).

**Вывод:** без NOPASSWD автоматизация по SSH не работает в принципе. Ansible устроен так же, поэтому в реальных проектах это стандарт.

### 10. WireGuard: handshake did not complete

**Что вижу:** в логе на Windows:
    Handshake for peer 1 (192.168.1.77:51820) did not complete after 5 seconds

**Почему:** в клиентском конфиге было AllowedIPs = 10.10.0.0/24, 192.168.1.0/24. Маршрут 192.168.1.0/24 создаётся через туннель, и запрос на 192.168.1.77:51820 тоже пытается уйти в тот же туннель, которого ещё нет. Петля.

**Что делать:** убрать 192.168.1.0/24 из клиентского AllowedIPs:
    AllowedIPs = 10.10.0.0/24

### 11. WireGuard: SSH обрывается при рестарте

**Что вижу:** после systemctl restart wg-quick@wg0 SSH-сессия к vm-vpn отвалилась.

**Почему:** в серверном конфиге было AllowedIPs = 10.10.0.2/32, 192.168.1.0/24. wg-quick создаёт маршрут 192.168.1.0/24 dev wg0, и весь трафик к домашней сети уходит в туннель, где никого нет.

**Что делать:** AllowedIPs = 10.10.0.2/32, только VPN-адрес клиента.

**Вывод:** на сервере нельзя указывать локальную сеть в AllowedIPs. Только VPN-адрес клиента.

### 12. WireGuard: MASQUERADE без -s ломает сеть

**Что вижу:** после старта WireGuard пинг до соседней VM падает.

**Почему:** правило iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE без указания источника. Маскарадится весь исходящий трафик через enp0s3, включая пинги к соседям. Обратный маршрут ломается.

**Что делать:**
    iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o enp0s3 -j MASQUERADE

-s 10.10.0.0/24 маскарадит только VPN-клиентов.

### 13. iptables -F POSTROUTING обрывает SSH

**Что вижу:** после sudo iptables -t nat -F POSTROUTING SSH отвалился.

**Почему:** команда сбрасывает всю таблицу NAT. Существующие TCP-сессии теряют состояние трекинга.

**Что делать:** не делать на живой системе без нужды. Если делать, то из консоли VirtualBox, а не по SSH.

**Вывод:** отладка сети только из консоли VirtualBox. SSH это твой единственный канал, потеряешь, восстановить сложно.

### 14. chmod: Operation not permitted на скриптах

**Что вижу:** chmod +x check_services.sh падает с Operation not permitted.

**Почему:** файлы созданы через sudo vi, владелец root.

**Что делать:**
    sudo chown admin:admin ~/scripts/*.sh
    chmod +x ~/scripts/*.sh

**Вывод:** не создавать свои файлы через sudo vi. Если очень нужно, потом вернуть владельца себе.

### 15. cron: логи не пишутся в /var/log

**Что вижу:** после настройки cron файл /var/log/check_services.log не создаётся.

**Почему:** cron запускает задачу от admin, а в /var/log/ писать может только root.

**Что делать:** логи в домашнюю папку:
    */15 * * * * /home/admin/scripts/check_services.sh >> /home/admin/logs/check_services.log 2>&1

disk_report.sh пишет в /var/log/homelab/disk_report.log (по ТЗ). Файл создан с владельцем admin, поэтому пишется без sudo.

### 16. lynis: command -v пусто через sudo

**Что вижу:** ssh user@host "sudo command -v lynis" возвращает пусто, хотя lynis установлен.

**Почему:** command это shell builtin. sudo не умеет вызывать builtins.

**Что делать:**
    ssh user@host "sudo sh -c 'command -v lynis >/dev/null'"

sh -c '...' запускает новый shell под sudo, и command работает.

### 17. lynis на Rocky: пустой отчёт

**Что вижу:** lynis на Rocky создаёт файл 0 байт.

**Почему:** флаг --quiet в новых версиях lynis подавляет весь вывод, включая нужный.

**Что делать:** заменить --quick --quiet на --quick --no-colors.

### 18. lynis: PID-файл остаётся от прерванного запуска

**Что вижу:**
    Warning: PID file exists, probably another Lynis process is running.

**Почему:** предыдущий запуск прервали через Ctrl+C, PID-файл не удалился.

**Что делать:** в security_audit.sh уже встроено:
    ssh user@host "sudo rm -f /var/run/lynis.pid /tmp/lynis.pid"

---

## Скрипты автоматизации

Все лежат в /home/admin/scripts/ на vm-ctrl. Запускаются через cron.

### check_services.sh

Проверяет ключевые сервисы на всех VM. Различает «хост недоступен» и «сервис упал». Каждые 15 минут. Пишет в ~/logs/check_services.log плюс syslog при падении.

Что проверяет:
- vm-web: nginx, pyserver
- vm-dns: pihole-FTL
- vm-vpn: wg-quick@wg0
- vm-legacy: nginx

### backup_nginx.sh

Забирает /etc/nginx с vm-web по SSH, пакует, проверяет целостность (stat + tar -tzf), удаляет битые и пустые. Раз в день в 03:00. Хранит в /var/backups/nginx/, 7 последних.

Предварительный шаг один раз: ssh admin@192.168.1.82 "sudo setfacl -R -m u:admin:rx /etc/nginx", чтобы admin мог читать конфиг без sudo.

### disk_report.sh

Собирает df -h и du -sh /var/log со всех VM. Каждый час. Пишет в /var/log/homelab/disk_report.log (файл создан с владельцем admin, поэтому без sudo).

### security_audit.sh

Запускает lynis audit system на всех VM. Правильно отличает rc=1/2 (lynis нашёл проблемы, это норма) от rc>2 или 255 (реальная ошибка SSH/sudo). По воскресеньям в 04:00. Отчёты в /var/log/lynis/<vm>-YYYY-MM-DD.log.

---

## Cron

Формат: минута, час, день_месяца, месяц, день_недели, команда.

Мой crontab:

    */15 * * * * /home/admin/scripts/check_services.sh  >> /home/admin/logs/check_services.log 2>&1
    0    * * * * /home/admin/scripts/disk_report.sh     >  /home/admin/logs/disk_report.cron.log 2>&1
    0    3 * * * /home/admin/scripts/backup_nginx.sh    >> /home/admin/logs/backup_nginx.log 2>&1
    0    4 * * 0 /home/admin/scripts/security_audit.sh >> /home/admin/logs/security_audit.log 2>&1

Задачи разнесены по времени, чтобы не стартовали одновременно. disk_report в :00, backup в 03:00, audit в 04:00 воскресенья. check_services каждые 15 минут.

disk_report.sh использует > (перезапись) для .cron.log, чтобы не путать вывод cron с самим отчётом. Отчёт пишется в /var/log/homelab/disk_report.log.

Проверка:
    crontab -l
    sudo systemctl status cron
    cat ~/logs/check_services.log

---

## Git

Зачем: история версий, резервная копия на GitHub, портфолио.

Структура:

    ~/home_lab/
    ├── README.md
    ├── .gitignore
    ├── LICENSE
    ├── configs/
    │   ├── ssh/99-hardening.conf
    │   ├── netplan/50-static-vm-ctrl.yaml
    │   ├── ufw/rules-vm-web.txt
    │   ├── firewalld/rules-vm-legacy.txt
    │   ├── wireguard/wg0.server.conf      # ключи = REDACTED
    │   ├── wireguard/wg0.client.conf      # ключи = REDACTED
    │   └── systemd/pyserver.service
    └── scripts/
        ├── check_services.sh
        ├── backup_nginx.sh
        ├── disk_report.sh
        └── security_audit.sh

.gitignore:

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

Команды:
    cd ~/home_lab
    git add .
    git commit -m "..."
    git push

Перед коммитом всегда git status и проверить, что нет id_*, *.key, *.pem, *.tar.gz.

Удалённый репозиторий:
- URL: git@github.com:al-kv/Homelab-DevOps-Engineer.git
- Ветка: main

Если push rejected (non-fast-forward):
    git pull --rebase origin main
    git push -u origin main

---

## SELinux на Rocky: что чинили и почему

getenforce показал Enforcing. Nginx запустился, но страницу не отдавал (curl http://192.168.1.62/ падал с 403). Причина: SELinux по умолчанию запрещает процессу httpd_t инициировать сетевые соединения. У меня Nginx работает как reverse-proxy, ходит на 127.0.0.1:9000. Значит нужно разрешить:

    sudo setsebool -P httpd_can_network_connect on

-P чтобы флаг сохранился после перезагрузки. После этого страница отдалась.

Для нестандартного порта (например, 8080) дополнительно:
    sudo semanage port -a -t http_port_t -p tcp 8080

Проверка: sudo semanage port -l | grep http_port_t, порт 8080 должен быть в списке. policycoreutils-python-utils установлен, он нужен для semanage.

---

## Отступления от ТЗ

- Юзеры admin/admin1/student вместо ansible. Функционально одно и то же: непривилегированный пользователь с NOPASSWD sudo. AllowUsers прописан в configs/ssh/99-hardening.conf под каждого.
- IP-адреса реальные из моей лабы (192.168.1.131, .82, .94, .77, .62), а не 192.168.1.101-105 из ТЗ. В ТЗ указано «пример».
- backup_nginx.sh пишет в /var/backups/nginx/ (по ТЗ). Папка создана с владельцем admin, чтобы cron-задача писала без sudo.
- disk_report.sh пишет в /var/log/homelab/disk_report.log (по ТЗ). Файл создан с владельцем admin по той же причине.
- security_audit.sh различает rc=1/2 (lynis нашёл проблемы, это норма) от rc>2 или 255 (реальная ошибка SSH/sudo). Оригинальный скрипт падал целиком при первом же замечании lynis.

---

## Доказательства работы VPN

С Windows-клиента WireGuard после подключения:

    ping 10.10.0.1     # шлюз wg0. Windows firewall блокирует ICMP-reply, на функционал не влияет
    ping 192.168.1.94  # vm-dns. Пингуется

(192.168.1.94 это реальный IP vm-dns в моей лабе. В ТЗ указан .103 как пример.)

sudo wg show на vm-vpn:
    interface: wg0
      listening port: 51820
    peer: CLIENT_PUBLIC_KEY
      allowed ips: 10.10.0.2/32

NAT настроен корректно. iptables -t nat -L POSTROUTING -n показывает MASQUERADE all -- 10.10.0.0/24 0.0.0.0/0.

---

## Планы по улучшению

Проект полностью рабочий, но идеальным он не бывает. Вот что можно сделать дальше:

- **Ротация логов:** настроить logrotate для /var/log/homelab/disk_report.log и ~/logs/*.log.
- **Линтеры:** прогнать shellcheck по всем скриптам и добавить вывод в репозиторий.
- **Инфраструктура как код:** этот же проект уже автоматизирован через Ansible (ссылка на репозиторий в самом начале).

---

---

## Как развернуть у себя

Это учебный проект для портфолио, а не готовый инсталлятор. Чтобы повторить у себя, сделай так:

1. Поднять 5 VM (Ubuntu 24.04, Ubuntu 24.04, Ubuntu 24.04, Debian 13, Rocky 9.8). Bridged Adapter, статические IP в одной подсети.
2. Заменить IP-адреса в scripts/*.sh и configs/* на свои.
3. Заменить имена пользователей (admin, admin1, student) на свои в скриптах и в configs/ssh/99-hardening.conf.
4. Настроить SSH-ключи. С vm-ctrl сгенерировать ssh-keygen -t ed25519, публичный ключ положить в authorized_keys на 4 остальных VM.
5. Установить пакеты по списку из ТЗ Блока 1.
6. Скопировать configs/* на соответствующие VM, применить (netplan apply, ufw enable и так далее).
7. Заполнить свои значения в configs/wireguard/*.conf (ключи WireGuard).
8. crontab -e на vm-ctrl, вставить 4 строки из раздела «Cron».
9. Проверить: ~/home_lab/scripts/check_services.sh должен вывести все [OK].

---

**Конец README.**
