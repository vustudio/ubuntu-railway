#!/usr/bin/env bash
# Boot order: prep persistent filestore on the volume -> render odoo.conf from env ->
# start Odoo (background, self-respawning) -> exec ttyd as the long-lived foreground process.
set -euo pipefail

VOL=/root/odoo
FILESTORE="$VOL/data"          # Odoo data_dir, lives on the persistent /root volume
LOGDIR=/var/log/odoo
CONF=/etc/odoo/odoo.conf
BACKUP_FILESTORE="$(ls -d /root/odoo-backup-*/data/var-lib-odoo.tar.gz 2>/dev/null | head -1 || true)"

# /root (the volume mount) is 700 by default; let the unprivileged odoo user traverse into it.
chmod 711 /root || true
mkdir -p "$VOL" "$FILESTORE" "$LOGDIR" /etc/odoo
chown -R odoo:odoo "$VOL" "$LOGDIR"

# First boot: seed the filestore from the on-volume backup if the volume copy is empty.
if [ -z "$(ls -A "$FILESTORE" 2>/dev/null || true)" ] && [ -n "${BACKUP_FILESTORE:-}" ]; then
  echo "[entrypoint] seeding filestore from $BACKUP_FILESTORE"
  tmp="$(mktemp -d)"
  tar -xzf "$BACKUP_FILESTORE" -C "$tmp"
  if [ -d "$tmp/var/lib/odoo" ]; then
    cp -a "$tmp/var/lib/odoo/." "$FILESTORE/"
  fi
  rm -rf "$tmp"
  chown -R odoo:odoo "$FILESTORE"
fi

# Odoo + its addons expect /var/lib/odoo — point it at the volume-backed dir.
rm -rf /var/lib/odoo
ln -sfn "$FILESTORE" /var/lib/odoo

# Render odoo.conf from env each boot (keeps DB creds + master hash out of the image).
cat > "$CONF" <<EOF
[options]
admin_passwd = ${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD not set}
db_host = ${ODOO_DB_HOST:?ODOO_DB_HOST not set}
db_port = ${ODOO_DB_PORT:-5432}
db_user = ${ODOO_DB_USER:-odoo}
db_password = ${ODOO_DB_PASSWORD:?ODOO_DB_PASSWORD not set}
db_name = ${ODOO_DB_NAME:-Vu1}
dbfilter = ^${ODOO_DB_NAME:-Vu1}\$
data_dir = ${FILESTORE}
http_port = 8069
proxy_mode = True
default_productivity_apps = True
logfile = ${LOGDIR}/odoo-server.log
EOF
chown odoo:odoo "$CONF"
chmod 640 "$CONF"

# Start Odoo as the odoo user, self-respawning on crash, in the background.
(
  while true; do
    echo "[entrypoint] starting odoo $(date -u +%FT%TZ)"
    runuser -u odoo -- /usr/bin/odoo -c "$CONF" || true
    echo "[entrypoint] odoo exited; restarting in 5s"
    sleep 5
  done
) &

# ttyd is the foreground/PID-1 process: keeps the container alive and preserves web-terminal access.
exec /bin/ttyd -p "${PORT:-8080}" -c "${USERNAME:-admin}:${PASSWORD:-changeme}" /bin/bash
