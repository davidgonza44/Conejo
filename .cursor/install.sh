#!/usr/bin/env bash
# Setup idempotente del entorno de desarrollo para Cloud Agents.
# - Instala MySQL 8 y utilidades de Python (paquetes del sistema).
# - Crea el entorno virtual e instala dependencias.
# - Arranca MySQL (datadir en tmpfs) y siembra la base de datos.
#
# Nota: el datadir de MySQL vive en tmpfs (ver .cursor/mysql_boot.sh), por lo
# que NO persiste en el snapshot. El comando `start` vuelve a inicializarlo y
# a sembrarlo en cada arranque; aquí se ejecuta también para validar el setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive

echo "==> Instalando paquetes del sistema (mysql-server, python3-venv)"
sudo apt-get update -qq
sudo apt-get install -y -qq mysql-server python3-venv python3-pip

echo "==> Creando entorno virtual e instalando dependencias"
python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install -r requirements.txt -q

echo "==> Preparando archivo .env de desarrollo (si no existe)"
if [ ! -f .env ]; then
  cp .cursor/dev.env .env
fi

echo "==> Arrancando MySQL y sembrando la base de datos"
bash .cursor/mysql_boot.sh
./venv/bin/python scripts/init_db.py

echo "==> Setup completado."
