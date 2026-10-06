#!/bin/bash
# backup_nginx.sh — забрать /etc/nginx с vm-web, оставить 7 последних
# ПРЕДВАРИТЕЛЬНО: ssh admin@192.168.1.82 "sudo setfacl -R -m u:admin:rx /etc/nginx"

set -euo pipefail

BACKUP_DIR="/backup/nginx"
REMOTE_HOST="admin@192.168.1.82"
REMOTE_SRC="/etc/nginx"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE_NAME="nginx-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "[*] Забираю $REMOTE_SRC с $REMOTE_HOST..."
ssh -o BatchMode=yes "$REMOTE_HOST" "tar -czf - $REMOTE_SRC" > "$BACKUP_DIR/$ARCHIVE_NAME"

echo "[*] Чищу старые (оставляю 7)..."
ls -t "$BACKUP_DIR"/nginx-*.tar.gz | tail -n +8 | xargs -r rm -f

echo "[OK] Готово: $ARCHIVE_NAME"
du -sh "$BACKUP_DIR/$ARCHIVE_NAME"
