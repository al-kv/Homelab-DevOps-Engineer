#!/bin/bash
# backup_nginx.sh — забрать /etc/nginx с vm-web, оставить 7 последних
# Предварительно (один раз): ssh admin@192.168.1.82 "sudo setfacl -R -m u:admin:rx /etc/nginx"
set -euo pipefail

BACKUP_DIR="/backup/nginx"
REMOTE_HOST="admin@192.168.1.82"
REMOTE_SRC="/etc/nginx"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE_NAME="nginx-$DATE.tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
MIN_SIZE=1024  # 1KB — архив не должен быть пустым

mkdir -p "$BACKUP_DIR"

echo "[*] Забираю $REMOTE_SRC с $REMOTE_HOST..."

# Проверяем что архив скачался И валиден как gzip
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" \
        "tar -czf - $REMOTE_SRC" > "$ARCHIVE_PATH"; then
    echo "[FAIL] SSH/tar error на $REMOTE_HOST"
    rm -f "$ARCHIVE_PATH"
    exit 1
fi

# Проверка размера
if [ "$(stat -c%s "$ARCHIVE_PATH")" -lt "$MIN_SIZE" ]; then
    echo "[FAIL] Архив слишком мал, удаляю"
    rm -f "$ARCHIVE_PATH"
    exit 1
fi

# Проверка целостности gzip
if ! tar -tzf "$ARCHIVE_PATH" > /dev/null 2>&1; then
    echo "[FAIL] Битый архив, удаляю"
    rm -f "$ARCHIVE_PATH"
    exit 1
fi

echo "[*] Чищу старые (оставляю 7)..."
# find надёжнее ls: не падает на пустой директории, не ловит пробелы в именах
find "$BACKUP_DIR" -maxdepth 1 -name 'nginx-*.tar.gz' -type f -printf '%T@ %p\n' \
    | sort -rn | tail -n +8 | cut -d' ' -f2- | xargs -r rm -f

echo "[OK] Готово: $ARCHIVE_NAME ($(du -h "$ARCHIVE_PATH" | cut -f1))"
