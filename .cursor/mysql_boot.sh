#!/usr/bin/env bash
# Arranca MySQL de forma robusta en los pods de Cloud Agent.
#
# Por qué el datadir vive en tmpfs (/dev/shm):
#   El sistema de archivos overlay persistente de los pods (al bootear desde un
#   snapshot) NO es compatible con las operaciones de archivo de InnoDB: mysqld
#   muere al arrancar con "Operating system error number 22 in a file
#   operation" con cualquier innodb_flush_method. Un datadir en tmpfs funciona
#   de forma fiable. Como los datos son de desarrollo (semilla) y se regeneran
#   en cada arranque con scripts/init_db.py, su volatilidad es aceptable.
#
# Por qué --no-defaults:
#   Evita /etc/mysql (que fija datadir=/var/lib/mysql y un error log no
#   escribible tras restaurar el snapshot). Se pasan las opciones necesarias de
#   forma explícita.
set -euo pipefail

DATADIR=/dev/shm/mysql-data
SOCK=/var/run/mysqld/mysqld.sock
ERRLOG=/var/run/mysqld/mysqld.err

sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld

if sudo mysqladmin --socket="$SOCK" ping >/dev/null 2>&1; then
  echo "==> MySQL ya está en ejecución."
  exit 0
fi

sudo rm -f /var/run/mysqld/*.pid /var/run/mysqld/*.sock 2>/dev/null || true

sudo mkdir -p "$DATADIR"
sudo chown mysql:mysql "$DATADIR"
if [ ! -d "$DATADIR/mysql" ]; then
  echo "==> Inicializando datadir de MySQL en tmpfs ($DATADIR)"
  sudo -u mysql /usr/sbin/mysqld --no-defaults --datadir="$DATADIR" \
    --initialize-insecure --log-error="$ERRLOG"
fi

echo "==> Arrancando mysqld (datadir en tmpfs)"
sudo -u mysql bash -c "nohup /usr/sbin/mysqld --no-defaults \
  --datadir='$DATADIR' --socket='$SOCK' --pid-file=/var/run/mysqld/mysqld.pid \
  --port=3306 --bind-address=127.0.0.1 \
  --log-error='$ERRLOG' --user=mysql >/dev/null 2>&1 &"

for _ in $(seq 1 90); do
  if sudo mysqladmin --socket="$SOCK" ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! sudo mysqladmin --socket="$SOCK" ping >/dev/null 2>&1; then
  echo "!! MySQL no arrancó a tiempo. Últimas líneas del log:" >&2
  sudo tail -n 40 "$ERRLOG" 2>/dev/null || true
  exit 1
fi
echo "==> MySQL está listo."

echo "==> Asegurando usuario de base de datos (idempotente)"
sudo mysql --no-defaults -uroot --socket="$SOCK" <<'SQL'
CREATE USER IF NOT EXISTS 'app_user'@'localhost' IDENTIFIED BY 'app_password';
CREATE USER IF NOT EXISTS 'app_user'@'127.0.0.1' IDENTIFIED BY 'app_password';
GRANT ALL PRIVILEGES ON *.* TO 'app_user'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'app_user'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
