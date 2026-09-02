#!/usr/bin/env bash
# Reconciliación por arranque: garantiza que MySQL esté en ejecución.
# Los datos ya viven en /var/lib/mysql (persistidos en el snapshot); aquí
# solo hace falta arrancar el demonio.
set -euo pipefail

echo "==> Arrancando MySQL"
sudo service mysql start

# Espera breve hasta que MySQL acepte conexiones.
for i in $(seq 1 30); do
  if sudo mysqladmin ping >/dev/null 2>&1; then
    echo "==> MySQL está listo."
    exit 0
  fi
  sleep 1
done

echo "!! MySQL no respondió a tiempo." >&2
exit 1
