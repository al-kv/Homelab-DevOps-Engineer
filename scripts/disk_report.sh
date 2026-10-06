#!/bin/bash
# disk_report.sh — собрать df и du /var/log со всех VM
# Запуск: ./disk_report.sh
# Результат: дописывает в /var/log/disk_report.log

set -euo pipefail

LOG_FILE="/var/log/disk_report.log"

# список VM: "user@host:label"
HOSTS=(
    "admin@192.168.1.82:vm-web"
    "admin@192.168.1.94:vm-dns"
    "admin1@192.168.1.77:vm-vpn"
    "student@192.168.1.62:vm-legacy"
)

# шапка отчёта
{
    echo ""
    echo "================================================================"
    echo "Отчёт: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
} | sudo tee -a "$LOG_FILE" > /dev/null

for entry in "${HOSTS[@]}"; do
    host="${entry%%:*}"        # всё до двоеточия
    label="${entry##*:}"       # всё после двоеточия

    {
        echo ""
        echo "--- $label ($host) ---"
        echo "df -h:"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "df -h" 2>&1 || echo "  [недоступен]"
        echo ""
        echo "du -sh /var/log:"
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "sudo du -sh /var/log" 2>&1 || echo "  [недоступен]"
    } | sudo tee -a "$LOG_FILE" > /dev/null
done

echo "[OK] Отчёт добавлен в $LOG_FILE"
