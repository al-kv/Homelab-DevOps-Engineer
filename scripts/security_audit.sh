#!/bin/bash
# security_audit.sh — lynis на всех VM. lynis возвращает 1/2 при находках - это НЕ ошибка.
set -uo pipefail   # без -e: обрабатываем ошибки сами, по хосту
                    # (pipefail оставил, но ловим явно)

REPORT_DIR="/var/log/lynis"
DATE=$(date +%Y-%m-%d)
FAILED=0

HOSTS=(
    "admin@192.168.1.82:vm-web"
    "admin@192.168.1.94:vm-dns"
    "admin1@192.168.1.77:vm-vpn"
    "student@192.168.1.62:vm-legacy"
)

if ! sudo -n true 2>/dev/null; then
    echo "[FAIL] Нужен NOPASSWD sudo на vm-ctrl"
    exit 1
fi

sudo mkdir -p "$REPORT_DIR"

for entry in "${HOSTS[@]}"; do
    host="${entry%%:*}"
    label="${entry##*:}"
    report_file="$REPORT_DIR/${label}-${DATE}.log"

    echo "[*] $label ($host)..."

    # Чистим залипший PID (см. README проблема 18) — превентивно
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
        "sudo rm -f /var/run/lynis.pid /tmp/lynis.pid" >/dev/null 2>&1 || true

    # Проверка наличия lynis
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
            "sudo sh -c 'command -v lynis >/dev/null'" 2>/dev/null; then
        echo "[SKIP] lynis не установлен на $label"
        FAILED=$((FAILED+1))
        continue
    fi

    # Запуск lynis. lynis rc=1/2 при находках — это норма, не считаем ошибкой.
    set +e
    ssh -o BatchMode=yes -o ConnectTimeout=60 "$host" \
        "sudo lynis audit system --quick --no-colors" 2>&1 \
        | sudo tee "$report_file" > /dev/null
    rc=$?
    set -e
    if [ $rc -gt 2 ] || [ $rc -eq 255 ]; then
        # >2 — что-то реально пошло не так (SSH, sudo, OOM)
        echo "[FAIL] $label: rc=$rc"
        rm -f "$report_file"
        FAILED=$((FAILED+1))
    else
        echo "[OK] $label (lynis rc=$rc)"
    fi
done

echo ""
echo "=== Отчёты в $REPORT_DIR ==="
ls -la "$REPORT_DIR" || true

[ $FAILED -eq 0 ] && exit 0 || exit 1
