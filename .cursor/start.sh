#!/usr/bin/env bash
# Reconciliación por arranque: garantiza que MySQL esté en ejecución.
# Los datos viven en /var/lib/mysql (persistidos en el snapshot); aquí solo
# hace falta arrancar el demonio de forma limpia en cada boot.
set -euo pipefail

echo "==> Preparando directorio de runtime de MySQL"
sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld

# El snapshot puede contener archivos .pid obsoletos de un mysqld anterior.
# Se eliminan solo si MySQL no está aceptando conexiones todavía.
if ! sudo mysqladmin ping >/dev/null 2>&1; then
  echo "==> Limpiando PID/sockets obsoletos"
  sudo rm -f /var/lib/mysql/*.pid /var/run/mysqld/*.pid /var/run/mysqld/*.sock 2>/dev/null || true
fi

echo "==> Arrancando MySQL"
sudo service mysql start || true

# Espera hasta que MySQL acepte conexiones.
for _ in $(seq 1 60); do
  if sudo mysqladmin ping >/dev/null 2>&1; then
    echo "==> MySQL está listo."
    exit 0
  fi
  sleep 1
done

echo "!! MySQL no respondió a tiempo." >&2
sudo tail -n 30 /var/log/mysql/error.log 2>/dev/null || true
exit 1
