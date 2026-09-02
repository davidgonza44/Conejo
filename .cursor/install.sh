#!/usr/bin/env bash
# Setup idempotente del entorno de desarrollo para Cloud Agents.
# - Instala MySQL 8 y utilidades de Python (paquetes del sistema).
# - Crea el entorno virtual e instala dependencias.
# - Arranca MySQL (datadir en tmpfs) y siembra la base de datos.
# - Instala binarios fijados de Gentle AI y Engram en /usr/local/bin.
#
# Nota: el datadir de MySQL vive en tmpfs (ver .cursor/mysql_boot.sh), por lo
# que NO persiste en el snapshot. El comando `start` vuelve a inicializarlo y
# a sembrarlo en cada arranque; aquí se ejecuta también para validar el setup.
#
# Gentle AI y Engram se instalan como software del Build, no como memoria
# precargada ni como una segunda fuente de reglas. No se ejecutan presets,
# `gentle-ai install`, `engram setup`, ni `engram mcp`.
#
# Uso aislado (sin MySQL ni semilla de la aplicación):
#   bash .cursor/install.sh --cloud-tools-only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive

# Versiones exactas del canal estable. No usar latest/main/master.
GENTLE_AI_VERSION="v2.5.0"
ENGRAM_VERSION="v1.20.0"
CLOUD_TOOLS_BIN_DIR="/usr/local/bin"
CLOUD_TOOLS_MAX_ARCHIVE_BYTES="$((128 * 1024 * 1024))"

# SHA-256 oficiales de checksums.txt en el tag fijado (linux).
GENTLE_AI_SHA256_LINUX_AMD64="2ba84a3a7ba2b1193019bde2acb05b02cbf222b667568c919686352b3caab113"
GENTLE_AI_SHA256_LINUX_ARM64="16a6243d17c146e3fc0024f6f005c5bd141fbb2dda4b56e269318e499ddc170b"
ENGRAM_SHA256_LINUX_AMD64="7dc3003318e303bee269a4772144f3ce01c8ec700bfd524aaec76770acd389ca"
ENGRAM_SHA256_LINUX_ARM64="7eb815910a76ae6cfa9a5d0161d3701e293dcca71f7743cffa62e236e5af59af"

cloud_tools_fail() {
  echo "!! $*" >&2
  exit 1
}

cloud_tools_linux_arch() {
  local uname_arch
  uname_arch="$(uname -m)"
  case "$uname_arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) cloud_tools_fail "Arquitectura no soportada para Gentle AI/Engram: ${uname_arch}" ;;
  esac
}

cloud_tools_version_matches() {
  local binary="$1"
  local expected="$2"
  local output
  if [ ! -x "$binary" ]; then
    return 1
  fi
  output="$("$binary" version 2>/dev/null || "$binary" --version 2>/dev/null || true)"
  [ -n "$output" ] && printf '%s' "$output" | grep -Fq "$expected"
}

cloud_tools_download() {
  local url="$1"
  local dest="$2"
  curl -fsSL --retry 3 --retry-delay 2 --max-filesize "$CLOUD_TOOLS_MAX_ARCHIVE_BYTES" \
    -o "$dest" "$url" || cloud_tools_fail "No se pudo descargar ${url}"
  local size
  size="$(wc -c < "$dest" | tr -d '[:space:]')"
  if [ "$size" -lt 64 ]; then
    cloud_tools_fail "Descarga demasiado pequeña (${size} bytes): ${url}"
  fi
  if [ "$size" -gt "$CLOUD_TOOLS_MAX_ARCHIVE_BYTES" ]; then
    cloud_tools_fail "Descarga excede el tope de 128 MiB: ${url}"
  fi
}

cloud_tools_install_release_binary() {
  local name="$1"
  local tag="$2"
  local repo="$3"
  local archive="$4"
  local expected_sha="$5"
  local dest="${CLOUD_TOOLS_BIN_DIR}/${name}"
  local version_number="${tag#v}"

  if cloud_tools_version_matches "$dest" "$version_number"; then
    echo "==> ${name} ${tag} ya está instalado en ${dest}; se reutiliza."
    return 0
  fi

  if [ -e "$dest" ]; then
    echo "==> Reemplazando ${name} existente en ${dest} por ${tag}"
  else
    echo "==> Instalando ${name} ${tag} en ${dest}"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local archive_path="${tmpdir}/${archive}"
  local checksums_path="${tmpdir}/checksums.txt"
  local download_base="https://github.com/${repo}/releases/download/${tag}"

  cloud_tools_download "${download_base}/checksums.txt" "$checksums_path"
  cloud_tools_download "${download_base}/${archive}" "$archive_path"

  if ! grep -Fq "$archive" "$checksums_path"; then
    cloud_tools_fail "${archive} no aparece en checksums.txt de ${tag}"
  fi

  (
    cd "$tmpdir"
    sha256sum --check --strict --ignore-missing checksums.txt
  ) || cloud_tools_fail "Falló la verificación SHA-256 oficial de ${archive}"

  local actual_sha
  actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
  if [ "$actual_sha" != "$expected_sha" ]; then
    cloud_tools_fail "SHA-256 de ${archive} no coincide con el digest fijado en install.sh"
  fi

  if [ "$name" = "gentle-ai" ]; then
    local minisig_path="${tmpdir}/checksums.txt.minisig"
    if curl -fsSL --retry 3 --retry-delay 2 -o "$minisig_path" \
      "${download_base}/checksums.txt.minisig"; then
      echo "==> checksums.txt.minisig de Gentle AI ${tag} descargado."
      echo "    Minisign no se verifica aquí: la clave pública oficial no vive en el repositorio"
      echo "    ni junto a los assets; hace falta un canal independiente del maintainer."
    else
      echo "!! No se pudo descargar checksums.txt.minisig de Gentle AI ${tag}" >&2
    fi
  fi

  tar -xzf "$archive_path" -C "$tmpdir"
  local extracted
  extracted="$(find "$tmpdir" -type f -name "$name" -perm -u+x | head -n 1)"
  if [ -z "$extracted" ]; then
    extracted="$(find "$tmpdir" -type f -name "$name" | head -n 1)"
  fi
  if [ -z "$extracted" ] || [ ! -f "$extracted" ]; then
    cloud_tools_fail "El archivo ${archive} no contiene el binario ${name}"
  fi
  chmod 0755 "$extracted"

  local staged="${tmpdir}/${name}.staged"
  cp "$extracted" "$staged"
  chmod 0755 "$staged"

  sudo install -m 0755 "$staged" "${dest}.tmp"
  sudo mv -f "${dest}.tmp" "$dest"

  if ! cloud_tools_version_matches "$dest" "$version_number"; then
    cloud_tools_fail "${name} quedó en ${dest} pero no reporta la versión ${version_number}"
  fi

  echo "==> ${name} ${tag} instalado en ${dest}"
}

install_cloud_agent_tools() {
  echo "==> Instalando herramientas fijadas de Cloud Agents (Gentle AI ${GENTLE_AI_VERSION}, Engram ${ENGRAM_VERSION})"

  if [ "$(uname -s)" != "Linux" ]; then
    cloud_tools_fail "Gentle AI/Engram del Cloud Build solo se instalan en Linux"
  fi

  for required in curl tar sha256sum sudo install; do
    command -v "$required" >/dev/null 2>&1 || cloud_tools_fail "Falta ${required} en PATH"
  done

  local arch
  arch="$(cloud_tools_linux_arch)"
  local gentle_sha engram_sha
  case "$arch" in
    amd64)
      gentle_sha="$GENTLE_AI_SHA256_LINUX_AMD64"
      engram_sha="$ENGRAM_SHA256_LINUX_AMD64"
      ;;
    arm64)
      gentle_sha="$GENTLE_AI_SHA256_LINUX_ARM64"
      engram_sha="$ENGRAM_SHA256_LINUX_ARM64"
      ;;
    *)
      cloud_tools_fail "Arquitectura Linux no prevista: ${arch}"
      ;;
  esac

  local gentle_archive="gentle-ai_${GENTLE_AI_VERSION#v}_linux_${arch}.tar.gz"
  local engram_archive="engram_${ENGRAM_VERSION#v}_linux_${arch}.tar.gz"

  cloud_tools_install_release_binary \
    "gentle-ai" \
    "$GENTLE_AI_VERSION" \
    "Gentleman-Programming/gentle-ai" \
    "$gentle_archive" \
    "$gentle_sha"

  cloud_tools_install_release_binary \
    "engram" \
    "$ENGRAM_VERSION" \
    "Gentleman-Programming/engram" \
    "$engram_archive" \
    "$engram_sha"

  echo "==> Binarios Cloud: $(command -v gentle-ai) $(command -v engram)"
}

install_application_runtime() {
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
}

if [ "${1:-}" = "--cloud-tools-only" ]; then
  install_cloud_agent_tools
  echo "==> Setup de herramientas Cloud completado."
  exit 0
fi

install_application_runtime
install_cloud_agent_tools

echo "==> Setup completado."
