#!/usr/bin/env bash
# Setup idempotente del entorno de desarrollo para Cloud Agents.
# - Instala MySQL 8 y utilidades de Python (paquetes del sistema).
# - Crea el entorno virtual e instala dependencias.
# - Prepara el usuario/base de datos de MySQL y los datos semilla.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive

echo "==> Instalando paquetes del sistema (mysql-server, python3-venv)"
sudo apt-get update -qq
sudo apt-get install -y -qq mysql-server python3-venv python3-pip

echo "==> Preparando directorio de runtime y arrancando MySQL para la inicialización"
sudo mkdir -p /var/run/mysqld
sudo chown mysql:mysql /var/run/mysqld
if ! sudo mysqladmin ping >/dev/null 2>&1; then
  sudo rm -f /var/lib/mysql/*.pid /var/run/mysqld/*.pid /var/run/mysqld/*.sock 2>/dev/null || true
fi
sudo service mysql start
for _ in $(seq 1 60); do
  sudo mysqladmin ping >/dev/null 2>&1 && break
  sleep 1
done

echo "==> Creando usuario de base de datos de desarrollo (idempotente)"
sudo mysql <<'SQL'
CREATE USER IF NOT EXISTS 'app_user'@'localhost' IDENTIFIED BY 'app_password';
CREATE USER IF NOT EXISTS 'app_user'@'127.0.0.1' IDENTIFIED BY 'app_password';
GRANT ALL PRIVILEGES ON *.* TO 'app_user'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'app_user'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

echo "==> Creando entorno virtual e instalando dependencias"
python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install -r requirements.txt -q

echo "==> Preparando archivo .env de desarrollo (si no existe)"
if [ ! -f .env ]; then
  cp .cursor/dev.env .env
fi

echo "==> Inicializando base de datos, tablas y datos semilla (idempotente)"
./venv/bin/python scripts/init_db.py

# Se detiene MySQL de forma limpia para que el snapshot generado por el build
# quede con un directorio de datos consistente (evita fallos de arranque en
# los pods que booteen desde el snapshot). El comando `start` lo vuelve a
# levantar en cada boot.
echo "==> Deteniendo MySQL de forma limpia (datadir consistente para el snapshot)"
sudo service mysql stop || true

echo "==> Setup completado."
