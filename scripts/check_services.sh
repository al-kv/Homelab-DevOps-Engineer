#!/bin/bash
# check_services.sh — проверка ключевых сервисов на всех VM
# Запуск: ./check_services.sh
# Результаты: вывод + запись в syslog через logger (только при падении)

# функция: принимает хост и сервис, проверяет статус
check_service() {
    local host="$1"
    local service="$2"

    # SSH с BatchMode (не спрашивает пароль) и таймаутом 5 сек
    local status
    status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "systemctl is-active $service" 2>/dev/null)

    if [ "$status" = "active" ]; then
        echo "[OK]   $host — $service"
    else
        echo "[FAIL] $host — $service (status: $status)"
        # пишем в syslog с тегом check_services
        logger -t check_services "$host: $service is DOWN (status: $status)"
    fi
}

echo "=== check_services: $(date '+%Y-%m-%d %H:%M:%S') ==="

# vm-web: nginx + pyserver
check_service admin@192.168.1.82 nginx
check_service admin@192.168.1.82 pyserver

# vm-dns: pihole-FTL
check_service admin@192.168.1.94 pihole-FTL

# vm-vpn: wg-quick@wg0
check_service admin1@192.168.1.77 wg-quick@wg0

# vm-legacy: nginx
check_service student@192.168.1.62 nginx

echo "=== done ==="
