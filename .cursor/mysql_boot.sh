#!/usr/bin/env bash
# Arranca MySQL de forma robusta en los pods de Cloud Agent.
#
# Por qué no se usa `service mysql start` / mysqld_safe:
#   Tras restaurar el snapshot en un pod, mysqld no puede abrir su error log
#   por defecto (/var/log/mysql/error.log) y muere ANTES de poder registrar
#   nada; mysqld_safe oculta el error y el init script agota su timeout de 30s.
#   Arrancar mysqld directamente con --log-error en un directorio de runtime
#   siempre escribible (/var/run/mysqld) evita el problema por completo.
set -euo pipefail

sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld

# Limpia PID/sockets obsoletos que el snapshot pudiera contener.
if ! sudo mysqladmin ping >/dev/null 2>&1; then
  sudo rm -f /var/lib/mysql/*.pid /var/run/mysqld/*.pid /var/run/mysqld/*.sock 2>/dev/null || true
fi

if sudo mysqladmin ping >/dev/null 2>&1; then
  echo "==> MySQL ya está en ejecución."
  exit 0
fi

# --innodb-use-native-aio=0: el AIO nativo de InnoDB (libaio io_submit) no es
#   compatible con el sandbox/overlay de los pods y provoca "Operating system
#   error number 22" al arrancar. Con AIO simulado (pread/pwrite) funciona.
echo "==> Arrancando mysqld (log en /var/run/mysqld/mysqld.err)"
sudo -u mysql bash -c 'nohup /usr/sbin/mysqld --user=mysql --innodb-use-native-aio=0 --log-error=/var/run/mysqld/mysqld.err >/dev/null 2>&1 &'

for _ in $(seq 1 90); do
  if sudo mysqladmin ping >/dev/null 2>&1; then
    echo "==> MySQL está listo."
    exit 0
  fi
  sleep 1
done

echo "!! MySQL no arrancó a tiempo. Últimas líneas del log:" >&2
sudo tail -n 40 /var/run/mysqld/mysqld.err 2>/dev/null || true
exit 1
