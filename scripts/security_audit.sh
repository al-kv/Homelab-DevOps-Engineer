#!/bin/bash
# security_audit.sh — запустить lynis audit system на всех VM
# Запуск: ./security_audit.sh
# Результат: /var/log/lynis/<vm>-YYYY-MM-DD.log

set -euo pipefail

REPORT_DIR="/var/log/lynis"
DATE=$(date +%Y-%m-%d)

HOSTS=(
    "admin@192.168.1.82:vm-web"
    "admin@192.168.1.94:vm-dns"
    "admin1@192.168.1.77:vm-vpn"
    "student@192.168.1.62:vm-legacy"
)

sudo mkdir -p "$REPORT_DIR"

for entry in "${HOSTS[@]}"; do
    host="${entry%%:*}"
    label="${entry##*:}"
    report_file="$REPORT_DIR/${label}-${DATE}.log"

    echo "[*] Запускаю lynis на $label ($host)..."

    # lynis надо ставить на каждой VM отдельно
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
        "sudo sh -c 'command -v lynis >/dev/null' || (echo 'lynis не установлен на $label'; exit 1)" || continue
    # запуск lynis, вывод — в файл через tee
    ssh -o BatchMode=yes -o ConnectTimeout=60 "$host" \
        "sudo lynis audit system --quick --no-colors" 2>&1 | sudo tee "$report_file" > /dev/null

    echo "[OK] Отчёт: $report_file"
done

echo ""
echo "=== Отчёты ==="
ls -la "$REPORT_DIR"
