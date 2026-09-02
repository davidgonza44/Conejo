#!/usr/bin/env bash
# Reconciliación por arranque: garantiza que MySQL esté en ejecución.
# Los datos viven en /var/lib/mysql (persistidos en el snapshot); aquí solo
# hace falta arrancar el demonio de forma limpia en cada boot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash .cursor/mysql_boot.sh
