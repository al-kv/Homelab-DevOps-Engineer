#!/bin/bash
# disk_report.sh — собрать df и du /var/log со всех VM
# Результат: ~/logs/disk_report.log (без sudo, без /var/log)
set -uo pipefail

LOG_FILE="/var/log/homelab/disk_report.log"
mkdir -p "$HOME/logs"

HOSTS=(
    "admin@192.168.1.82:vm-web"
    "admin@192.168.1.94:vm-dns"
    "admin1@192.168.1.77:vm-vpn"
    "student@192.168.1.62:vm-legacy"
)

{
    echo ""
    echo "================================================================"
    echo "Отчёт: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
} >> "$LOG_FILE"

for entry in "${HOSTS[@]}"; do
    host="${entry%%:*}"
    label="${entry##*:}"

    {
        echo ""
        echo "--- $label ($host) ---"
        echo "df -h:"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "df -h" 2>&1 || echo "  [недоступен]"
        echo ""
        echo "du -sh /var/log:"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "sudo du -sh /var/log" 2>&1 || echo "  [недоступен]"
    } >> "$LOG_FILE"
done

echo "[OK] Отчёт добавлен в $LOG_FILE"
