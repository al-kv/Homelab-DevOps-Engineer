#!/bin/bash
# check_services.sh — проверка ключевых сервисов на всех VM
set -uo pipefail  # не -e: хотим проверить все хосты, даже если один недоступен

mkdir -p "$HOME/logs"

check_service() {
    local host="$1"
    local service="$2"
    local status
    status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
             "systemctl is-active $service" 2>/dev/null) || true

    if [ "$status" = "active" ]; then
        echo "[OK]   $host — $service"
    elif [ -z "$status" ]; then
        echo "[FAIL] $host — $service (хост недоступен / SSH отвалился)"
        logger -t check_services "$host: unreachable or SSH failed, service=$service"
    else
        echo "[FAIL] $host — $service (status: $status)"
        logger -t check_services "$host: $service is DOWN (status: $status)"
    fi
}

echo "=== check_services: $(date '+%Y-%m-%d %H:%M:%S') ==="

check_service admin@192.168.1.82  nginx
check_service admin@192.168.1.82  pyserver
check_service admin@192.168.1.94  pihole-FTL
check_service admin1@192.168.1.77 wg-quick@wg0
check_service student@192.168.1.62 nginx

echo "=== done ==="
