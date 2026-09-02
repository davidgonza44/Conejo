#!/usr/bin/env bash
# Reconciliación por arranque:
# - Arranca MySQL (inicializa el datadir en tmpfs si hace falta).
# - Crea/verifica las tablas y datos semilla (idempotente).
# El datadir vive en tmpfs y no persiste entre boots, por eso se resiembra aquí.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash .cursor/mysql_boot.sh

if [ -x ./venv/bin/python ]; then
  echo "==> Verificando/sembrando la base de datos"
  ./venv/bin/python scripts/init_db.py
fi
