#!/usr/bin/env bash
# Setup idempotente del entorno de desarrollo para Cloud Agents.
# - Instala MySQL 8 y utilidades de Python (paquetes del sistema).
# - Crea el entorno virtual e instala dependencias.
# - Arranca MySQL (datadir en tmpfs) y siembra la base de datos.
# - Instala Node.js 22 fijado (>=22.16), binarios Gentle AI/Engram y Pi 0.84.4.
# - Tras Node v22.23.2, ejecuta npm ci (CodeGraph, Repomix, OpenSpec locales).
#
# Nota: el datadir de MySQL vive en tmpfs (ver .cursor/mysql_boot.sh), por lo
# que NO persiste en el snapshot. El comando `start` vuelve a inicializarlo y
# a sembrarlo en cada arranque; aquí se ejecuta también para validar el setup.
#
# Gentle AI, Engram y Pi se instalan como software del Build, no como memoria
# precargada ni como una segunda fuente de reglas. No se ejecutan presets,
# `gentle-ai install`, `engram setup`, ni `engram mcp`.
# Pi se instala pinneado (@earendil-works/pi-coding-agent@0.84.4, --ignore-scripts).
# No se instalan gentle-pi ni paquetes companion, ni se configura MCP/subagents.
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
NODE_VERSION="v22.23.2"
PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_VERSION="0.84.4"
# SHA-512 SRI of the published registry tarball bytes for PI_PACKAGE@PI_VERSION.
# Bind installation: npm pack -> hash the actual .tgz -> compare -> install that file.
PI_NPM_INTEGRITY="sha512-jmOlrqUmvhh/siNWFRXjYLJzhKFIHNsAQaysRwzQPQFnPAaV/vhqHsLH/MBsIISA1Rjj7WTUFR3nJrpXoLx39w=="
CLOUD_TOOLS_BIN_DIR="/usr/local/bin"
CLOUD_TOOLS_MAX_ARCHIVE_BYTES="$((128 * 1024 * 1024))"

# SHA-256 oficiales de checksums.txt en el tag fijado (linux).
GENTLE_AI_SHA256_LINUX_AMD64="2ba84a3a7ba2b1193019bde2acb05b02cbf222b667568c919686352b3caab113"
GENTLE_AI_SHA256_LINUX_ARM64="16a6243d17c146e3fc0024f6f005c5bd141fbb2dda4b56e269318e499ddc170b"
ENGRAM_SHA256_LINUX_AMD64="7dc3003318e303bee269a4772144f3ce01c8ec700bfd524aaec76770acd389ca"
ENGRAM_SHA256_LINUX_ARM64="7eb815910a76ae6cfa9a5d0161d3701e293dcca71f7743cffa62e236e5af59af"

# SHA-256 oficiales de https://nodejs.org/dist/v22.23.2/SHASUMS256.txt
NODE_SHA256_LINUX_X64="b294a556e639d64338823920e5866c21c02741742d2e1529ee1a225c1ec9252a"
NODE_SHA256_LINUX_ARM64="013b59cfd2819703a6f4a14ab891fc46fc2a4e3f5bcd92de3fb4929b43e35b30"

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

# First whitespace-delimited token that looks like a version. A leading "v"
# is stripped; prerelease/build suffixes are kept so 1.20.0-rc.1 != 1.20.0.
cloud_tools_version_token() {
  local output="$1"
  local token
  # shellcheck disable=SC2086
  for token in $output; do
    case "$token" in
      v[0-9]*.[0-9]*)
        printf '%s' "${token#v}"
        return 0
        ;;
      [0-9]*.[0-9]*)
        printf '%s' "$token"
        return 0
        ;;
    esac
  done
  return 1
}

cloud_tools_version_matches() {
  local binary="$1"
  local expected="$2"
  local output reported
  if [ ! -x "$binary" ]; then
    return 1
  fi
  output="$("$binary" version 2>/dev/null || "$binary" --version 2>/dev/null || true)"
  [ -n "$output" ] || return 1
  reported="$(cloud_tools_version_token "$output")" || return 1
  [ -n "$reported" ] && [ "$reported" = "${expected#v}" ]
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

# Prefix reuse gate for the official Node layout. npm is validated by the
# pinned Node executing the bundled npm-cli.js, not by PATH or #!/usr/bin/env.
cloud_tools_pinned_nodejs_prefix_ready() {
  local prefix="$1"
  local prefix_node="${prefix}/bin/node"
  local prefix_npm="${prefix}/bin/npm"
  local npm_cli="${prefix}/lib/node_modules/npm/bin/npm-cli.js"
  local node_ver npm_ver canonical_prefix canonical_npm canonical_cli
  [ -x "$prefix_node" ] || return 1
  [ -x "$prefix_npm" ] || return 1
  [ -f "$npm_cli" ] || return 1
  node_ver="$("$prefix_node" --version 2>/dev/null || true)"
  [ "$node_ver" = "$NODE_VERSION" ] || return 1
  if [ ! -x /usr/bin/readlink ]; then
    return 1
  fi
  canonical_prefix="$(/usr/bin/readlink -f "$prefix")" || canonical_prefix=""
  canonical_npm="$(/usr/bin/readlink -f "$prefix_npm")" || canonical_npm=""
  canonical_cli="$(/usr/bin/readlink -f "$npm_cli")" || canonical_cli=""
  [ -n "$canonical_prefix" ] && [ -n "$canonical_npm" ] && [ -n "$canonical_cli" ] || return 1
  canonical_prefix="${canonical_prefix%/}"
  canonical_npm="${canonical_npm%/}"
  canonical_cli="${canonical_cli%/}"
  [ "$canonical_npm" = "$canonical_cli" ] || return 1
  cloud_tools_path_is_beneath "$canonical_npm" "$canonical_prefix" || return 1
  npm_ver="$("$prefix_node" "$npm_cli" --version 2>/dev/null || true)"
  [ "$npm_ver" = "10.9.8" ] || return 1
  return 0
}

install_pinned_nodejs() {
  echo "==> Instalando Node.js ${NODE_VERSION} (oficial, >=22.16 para CodeGraph)"

  local dest_node="${CLOUD_TOOLS_BIN_DIR}/node"
  local dest_npm="${CLOUD_TOOLS_BIN_DIR}/npm"
  local prefix="/usr/local/lib/nodejs/node-${NODE_VERSION}"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    echo "==> Node.js ${NODE_VERSION} ya está en el prefijo fijado (${prefix}); se reutiliza."
  else
    local arch node_arch expected_sha
    arch="$(cloud_tools_linux_arch)"
    case "$arch" in
      amd64)
        node_arch="x64"
        expected_sha="$NODE_SHA256_LINUX_X64"
        ;;
      arm64)
        node_arch="arm64"
        expected_sha="$NODE_SHA256_LINUX_ARM64"
        ;;
      *)
        cloud_tools_fail "Arquitectura Linux no prevista para Node.js: ${arch}"
        ;;
    esac

    local archive="node-${NODE_VERSION}-linux-${node_arch}.tar.gz"
    local download_base="https://nodejs.org/dist/${NODE_VERSION}"
    local tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    cloud_tools_download "${download_base}/SHASUMS256.txt" "${tmpdir}/SHASUMS256.txt"
    cloud_tools_download "${download_base}/${archive}" "${tmpdir}/${archive}"

    if ! grep -Fq "$archive" "${tmpdir}/SHASUMS256.txt"; then
      cloud_tools_fail "${archive} no aparece en SHASUMS256.txt de ${NODE_VERSION}"
    fi
    (
      cd "$tmpdir"
      sha256sum --check --strict --ignore-missing SHASUMS256.txt
    ) || cloud_tools_fail "Falló la verificación SHA-256 oficial de ${archive}"

    local actual_sha
    actual_sha="$(sha256sum "${tmpdir}/${archive}" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
      cloud_tools_fail "SHA-256 de ${archive} no coincide con el digest fijado en install.sh"
    fi

    tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"
    local extracted="${tmpdir}/node-${NODE_VERSION}-linux-${node_arch}"
    if [ ! -x "${extracted}/bin/node" ]; then
      cloud_tools_fail "El archivo ${archive} no contiene bin/node"
    fi

    # npm/npx del tarball oficial son wrappers relativos a lib/node_modules.
    # Hay que conservar el prefijo completo, no copiar solo bin/.
    local staged="${prefix}.tmp"
    sudo rm -rf "$staged"
    sudo mkdir -p /usr/local/lib/nodejs
    sudo mv "$extracted" "$staged"
    # Harden staging before the live swap: ubuntu-owned extract must not
    # become the published prefix. Symlink modes are left alone.
    sudo chown -R root:root "$staged"
    sudo find "$staged" ! -type l -perm /022 -exec chmod go-w {} +
    if [ -n "$(sudo find "$staged" \( ! -user root -o ! -group root \) -print)" ]; then
      cloud_tools_fail "El prefijo Node en staging no quedó root:root"
    fi
    if [ -n "$(sudo find "$staged" ! -type l -perm /022 -print)" ]; then
      cloud_tools_fail "El prefijo Node en staging tiene escritura para group/others"
    fi
    sudo rm -rf "$prefix"
    sudo mv "$staged" "$prefix"
  fi

  # CASE A/B: republish dest links from the pinned prefix (idempotent).
  local name
  for name in node npm npx corepack; do
    if [ -e "${prefix}/bin/${name}" ]; then
      sudo ln -sfn "${prefix}/bin/${name}" "${CLOUD_TOOLS_BIN_DIR}/${name}"
    fi
  done

  if [ ! -x "${prefix}/bin/node" ] || [ ! -x "${prefix}/bin/npm" ]; then
    cloud_tools_fail "Pi requiere ${prefix}/bin/node y ${prefix}/bin/npm"
  fi
  if ! cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    cloud_tools_fail "el prefijo Node fijado no quedó listo (${prefix})"
  fi
  if ! cloud_tools_version_matches "$dest_node" "${NODE_VERSION#v}"; then
    cloud_tools_fail "node quedó en ${dest_node} pero no reporta ${NODE_VERSION}"
  fi
  echo "==> Node.js ${NODE_VERSION} listo en ${dest_node} (prefijo ${prefix})"

  # Cursor Cloud coloca /exec-daemon delante de /usr/local/bin. Si cargo/bin
  # existe y va primero en PATH, enlazar ahí evita que Node 22.14 del overlay
  # gane a la versión fijada. No se instala NVM/Volta/mise/asdf.
  if [ -d /usr/local/cargo/bin ]; then
    local tool
    for tool in node npm npx; do
      if [ -e "${CLOUD_TOOLS_BIN_DIR}/${tool}" ]; then
        sudo ln -sfn "${CLOUD_TOOLS_BIN_DIR}/${tool}" "/usr/local/cargo/bin/${tool}"
      fi
    done
    echo "==> Enlaces Node en /usr/local/cargo/bin para preceder /exec-daemon"
  fi
}

cloud_tools_link_cloud_bin() {
  local dest="$1"
  local name
  name="$(basename "$dest")"
  if [ ! -e "$dest" ]; then
    return 1
  fi
  if [ -d /usr/local/cargo/bin ]; then
    sudo ln -sfn "$dest" "/usr/local/cargo/bin/${name}"
  fi
}

# Path-component-safe containment. Both arguments must already be canonical
# and without a trailing slash. /trusted/prefix-evil is not under /trusted/prefix.
cloud_tools_path_is_beneath() {
  local child="$1"
  local parent="$2"
  child="${child%/}"
  parent="${parent%/}"
  [ -n "$child" ] && [ -n "$parent" ] || return 1
  case "$child" in
    "${parent}"/*) return 0 ;;
    *) return 1 ;;
  esac
}

cloud_tools_repo_contains_path() {
  local path="$1"
  local canonical_path canonical_root
  if [ ! -x /usr/bin/readlink ]; then
    return 0
  fi
  canonical_path="$(/usr/bin/readlink -f "$path")" || canonical_path=""
  canonical_root="$(/usr/bin/readlink -f "$ROOT")" || canonical_root=""
  [ -n "$canonical_path" ] && [ -n "$canonical_root" ] || return 0
  canonical_path="${canonical_path%/}"
  canonical_root="${canonical_root%/}"
  [ "$canonical_path" = "$canonical_root" ] || cloud_tools_path_is_beneath "$canonical_path" "$canonical_root"
}

cloud_tools_assert_outside_repo() {
  local path="$1"
  if cloud_tools_repo_contains_path "$path"; then
    cloud_tools_fail "el directorio temporal de Pi quedó dentro del repositorio (${path})"
  fi
}

cloud_tools_assert_pi_under_prefix() {
  local path="$1"
  local prefix="$2"
  local canonical_path canonical_prefix
  if [ ! -x /usr/bin/readlink ]; then
    cloud_tools_fail "readlink no está disponible para resolver pi"
  fi
  canonical_prefix="$(/usr/bin/readlink -f "$prefix")" || canonical_prefix=""
  canonical_path="$(/usr/bin/readlink -f "$path")" || canonical_path=""
  if [ -z "$canonical_prefix" ] || [ ! -d "$canonical_prefix" ]; then
    cloud_tools_fail "el prefijo Node fijado no es un directorio (${prefix})"
  fi
  if [ -z "$canonical_path" ]; then
    cloud_tools_fail "no se pudo resolver el destino de pi (${path})"
  fi
  canonical_prefix="${canonical_prefix%/}"
  canonical_path="${canonical_path%/}"
  case "$canonical_path" in
    /exec-daemon/*)
      cloud_tools_fail "pi resuelve a ${canonical_path}"
      ;;
  esac
  if ! cloud_tools_path_is_beneath "$canonical_path" "$canonical_prefix"; then
    cloud_tools_fail "pi (${path} -> ${canonical_path}) no está bajo el prefijo fijado (${canonical_prefix})"
  fi
}

cloud_tools_pi_mktemp_pack_dir() {
  local dir canonical_dir
  if [ ! -d /tmp ] || [ ! -w /tmp ]; then
    cloud_tools_fail "/tmp no está disponible para artefactos temporales de Pi"
  fi
  dir="$(mktemp -d --tmpdir=/tmp pi-pack.XXXXXX)" \
    || cloud_tools_fail "no se pudo crear el directorio temporal de Pi en /tmp"
  canonical_dir="$(/usr/bin/readlink -f "$dir")" || canonical_dir=""
  if [ -z "$canonical_dir" ]; then
    rm -rf "$dir"
    cloud_tools_fail "no se pudo canonicalizar el directorio temporal de Pi"
  fi
  if cloud_tools_repo_contains_path "$canonical_dir"; then
    rm -rf "$dir"
    cloud_tools_fail "el directorio temporal de Pi quedó dentro del repositorio (${canonical_dir})"
  fi
  printf '%s' "$canonical_dir"
}

# Sibling of the pack-dir helper. Returns 1 on failure so callers in `if`
# conditions can fail closed instead of inheriting HOME.
cloud_tools_pi_mktemp_probe_home() {
  local dir canonical_dir
  if [ ! -d /tmp ] || [ ! -w /tmp ]; then
    return 1
  fi
  dir="$(mktemp -d --tmpdir=/tmp pi-probe.XXXXXX)" || return 1
  canonical_dir="$(/usr/bin/readlink -f "$dir")" || canonical_dir=""
  if [ -z "$canonical_dir" ]; then
    rm -rf "$dir"
    return 1
  fi
  if cloud_tools_repo_contains_path "$canonical_dir"; then
    rm -rf "$dir"
    return 1
  fi
  printf '%s' "$canonical_dir"
}

cloud_tools_pi_npm_pack() {
  local npm_bin="$1"
  local package="$2"
  local version="$3"
  local pack_dir="$4"
  (
    cd -- "$pack_dir" || exit 1
    npm_config_ignore_scripts=true "$npm_bin" pack "${package}@${version}" \
      --pack-destination "$pack_dir"
  ) || cloud_tools_fail "npm pack falló para ${package}@${version}"
}

cloud_tools_pi_reuse_if_ready() {
  local prefix="$1"
  local prefix_pi="$2"
  [ -x "$prefix_pi" ] || return 1
  cloud_tools_assert_pi_under_prefix "$prefix_pi" "$prefix"
  cloud_tools_pi_version_matches "$prefix_pi" "$PI_VERSION"
}

# Pi-only version probe. Never runs `pi version` (prompt-capable). Isolates HOME
# in a subshell so a RETURN trap cannot clobber the caller's pack-dir cleanup.
cloud_tools_pi_version_matches() {
  local binary="$1"
  local expected="$2"
  local probe_home output reported
  if [ ! -x "$binary" ]; then
    return 1
  fi
  probe_home=""
  if ! probe_home="$(cloud_tools_pi_mktemp_probe_home)"; then
    cloud_tools_fail "no se pudo crear un HOME temporal seguro para Pi"
  fi
  if [ -z "$probe_home" ]; then
    cloud_tools_fail "no se pudo crear un HOME temporal seguro para Pi"
  fi
  if ! output="$(
    trap 'rm -rf "$probe_home"' EXIT
    HOME="$probe_home" "$binary" --version 2>/dev/null
  )"; then
    return 1
  fi
  [ -n "$output" ] || return 1
  reported="$(cloud_tools_version_token "$output")" || return 1
  [ -n "$reported" ] && [ "$reported" = "${expected#v}" ]
}

cloud_tools_assert_pinned_pi_on_path() {
  local prefix="$1"
  local prefix_pi="$2"
  local pi_path resolved expected
  hash -r
  pi_path="$(command -v pi || true)"
  if [ -z "$pi_path" ]; then
    cloud_tools_fail "pi no quedó en PATH"
  fi
  if [ "$pi_path" = "/exec-daemon/pi" ]; then
    cloud_tools_fail "pi resolvió a /exec-daemon/pi; el enlace controlado no tiene precedencia"
  fi
  if [ ! -x "$pi_path" ]; then
    cloud_tools_fail "pi en ${pi_path} no es ejecutable"
  fi
  if [ ! -x "$prefix_pi" ]; then
    cloud_tools_fail "no hay pi en el prefijo Node fijado (${prefix_pi})"
  fi
  if [ ! -x /usr/bin/readlink ]; then
    cloud_tools_fail "readlink no está disponible para resolver pi"
  fi
  resolved="$(/usr/bin/readlink -f "$pi_path")" || resolved=""
  expected="$(/usr/bin/readlink -f "$prefix_pi")" || expected=""
  if [ -z "$resolved" ] || [ -z "$expected" ]; then
    cloud_tools_fail "no se pudo resolver el destino de pi (${pi_path} / ${prefix_pi})"
  fi
  case "$resolved" in
    /exec-daemon/*)
      cloud_tools_fail "pi resuelve a ${resolved}"
      ;;
  esac
  if [ "$resolved" != "$expected" ]; then
    cloud_tools_fail "pi en PATH (${pi_path} -> ${resolved}) no es el binario del prefijo fijado (${expected})"
  fi
  cloud_tools_assert_pi_under_prefix "$prefix_pi" "$prefix"
  cloud_tools_assert_pi_under_prefix "$pi_path" "$prefix"
}

cloud_tools_assert_ready_pi() {
  local prefix="$1"
  local prefix_pi="$2"
  local pi_path
  cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  pi_path="$(command -v pi || true)"
  if ! cloud_tools_pi_version_matches "$pi_path" "$PI_VERSION"; then
    cloud_tools_fail "pi en PATH no reporta ${PI_VERSION} con --version"
  fi
}

cloud_tools_sha512_sri() {
  local file="$1"
  local node_bin="$2"
  local sri
  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    cloud_tools_fail "no hay bytes para calcular SRI: ${file}"
  fi
  if [ ! -x "$node_bin" ]; then
    cloud_tools_fail "Node fijado no es ejecutable: ${node_bin}"
  fi
  sri="$(CLOUD_TOOLS_SRI_FILE="$file" "$node_bin" --input-type=commonjs -e '
const fs = require("fs");
const crypto = require("crypto");
const target = process.env.CLOUD_TOOLS_SRI_FILE;
const buf = fs.readFileSync(target);
process.stdout.write("sha512-" + crypto.createHash("sha512").update(buf).digest("base64"));
')" || cloud_tools_fail "no se pudo calcular SHA-512 SRI con ${node_bin}"
  if [ -z "$sri" ]; then
    cloud_tools_fail "SHA-512 SRI vacío para ${file}"
  fi
  printf '%s' "$sri"
}

cloud_tools_pi_install_verified_tarball() {
  local npm_bin="$1"
  local prefix="$2"
  local tarball="$3"
  if [ ! -f "$tarball" ]; then
    cloud_tools_fail "solo se instala el tarball verificado; no existe ${tarball}"
  fi
  case "$tarball" in
    *.tgz|*.tar.gz) ;;
    *)
      cloud_tools_fail "solo se instala el tarball verificado; se rechaza ${tarball}"
      ;;
  esac
  if [ -w "$prefix" ]; then
    "$npm_bin" install -g --prefix "$prefix" --ignore-scripts "$tarball"
  else
    echo "==> El prefix npm global no es escribible; se usa sudo"
    sudo "$npm_bin" install -g --prefix "$prefix" --ignore-scripts "$tarball"
  fi
}

cloud_tools_publish_pinned_pi() {
  local prefix="$1"
  local prefix_pi="$2"
  local dest="$3"
  if [ ! -x "$prefix_pi" ]; then
    cloud_tools_fail "npm install no dejó el binario pi en ${prefix_pi}"
  fi
  sudo ln -sfn "$prefix_pi" "$dest"
  cloud_tools_link_cloud_bin "$dest" || cloud_tools_fail "No se pudo publicar ${dest} en PATH"
  if [ -d /usr/local/cargo/bin ] && [ ! -e /usr/local/cargo/bin/pi ]; then
    cloud_tools_fail "no se publicó pi en /usr/local/cargo/bin"
  fi
  cloud_tools_assert_ready_pi "$prefix" "$prefix_pi"
}

install_pinned_pi() {
  echo "==> Instalando Pi ${PI_PACKAGE}@${PI_VERSION} (npm --ignore-scripts)"

  if [ "$PI_PACKAGE" != "@earendil-works/pi-coding-agent" ]; then
    cloud_tools_fail "PI_PACKAGE debe ser @earendil-works/pi-coding-agent; se rechaza ${PI_PACKAGE}"
  fi
  case "$PI_VERSION" in
    ""|latest|main|master|next)
      cloud_tools_fail "PI_VERSION debe ser exacta; se rechaza ${PI_VERSION:-vacío}"
      ;;
  esac

  hash -r
  local node_path npm_path node_ver npm_ver
  node_path="$(command -v node || true)"
  npm_path="$(command -v npm || true)"
  node_ver="$(node --version 2>/dev/null || true)"
  npm_ver="$(npm --version 2>/dev/null || true)"
  if [ "$node_ver" != "$NODE_VERSION" ]; then
    cloud_tools_fail "Pi requiere Node ${NODE_VERSION}; se encontró ${node_ver:-ninguno} (${node_path:-sin node})"
  fi
  if [ "$npm_ver" != "10.9.8" ]; then
    cloud_tools_fail "Pi requiere npm 10.9.8 del Node fijado; se encontró ${npm_ver:-ninguno} (${npm_path:-sin npm})"
  fi
  if [ "$node_path" = "/exec-daemon/node" ] || [ "$npm_path" = "/exec-daemon/npm" ]; then
    cloud_tools_fail "Pi no debe instalarse con /exec-daemon/node o /exec-daemon/npm"
  fi
  if [ -z "$npm_path" ]; then
    cloud_tools_fail "npm no está en PATH para instalar Pi"
  fi

  local prefix="/usr/local/lib/nodejs/node-${NODE_VERSION}"
  local npm_bin="${prefix}/bin/npm"
  local prefix_node="${prefix}/bin/node"
  local prefix_pi="${prefix}/bin/pi"
  local dest="${CLOUD_TOOLS_BIN_DIR}/pi"
  if [ ! -x "$npm_bin" ]; then
    cloud_tools_fail "No se encontró el npm fijado en ${npm_bin}"
  fi
  if [ ! -x "$prefix_node" ]; then
    cloud_tools_fail "No se encontró el node fijado en ${prefix_node}"
  fi

  if cloud_tools_pi_reuse_if_ready "$prefix" "$prefix_pi"; then
    cloud_tools_publish_pinned_pi "$prefix" "$prefix_pi" "$dest"
    echo "==> Pi ${PI_VERSION} ya está instalado; se reutiliza ($(command -v pi))."
    return 0
  fi

  echo "==> Empaquetando ${PI_PACKAGE}@${PI_VERSION} y verificando SRI del tarball"
  local pack_dir tgz candidate sri
  pack_dir="$(cloud_tools_pi_mktemp_pack_dir)"
  # EXIT covers cloud_tools_fail; RETURN covers a successful return.
  # shellcheck disable=SC2064
  trap "rm -rf '$pack_dir'" RETURN EXIT

  cloud_tools_pi_npm_pack "$npm_bin" "$PI_PACKAGE" "$PI_VERSION" "$pack_dir"

  tgz=""
  for candidate in "$pack_dir"/*.tgz; do
    if [ ! -f "$candidate" ]; then
      continue
    fi
    if [ -n "$tgz" ]; then
      cloud_tools_fail "npm pack escribió más de un tarball en ${pack_dir}"
    fi
    tgz="$candidate"
  done
  if [ -z "$tgz" ]; then
    cloud_tools_fail "npm pack no escribió un tarball en ${pack_dir}"
  fi

  sri="$(cloud_tools_sha512_sri "$tgz" "$prefix_node")"
  if [ "$sri" != "$PI_NPM_INTEGRITY" ]; then
    cloud_tools_fail "Integrity del tarball no coincide (calculada ${sri}; fijada ${PI_NPM_INTEGRITY})"
  fi
  echo "==> SRI del tarball verificado: ${sri}"

  cloud_tools_pi_install_verified_tarball "$npm_bin" "$prefix" "$tgz"
  cloud_tools_publish_pinned_pi "$prefix" "$prefix_pi" "$dest"

  local verify_node verify_npm
  verify_node="$(node --version 2>/dev/null || true)"
  verify_npm="$(npm --version 2>/dev/null || true)"
  if [ "$verify_node" != "$NODE_VERSION" ] || [ "$verify_npm" != "10.9.8" ]; then
    cloud_tools_fail "Tras instalar Pi, Node/npm ya no coinciden (${verify_node:-?} / ${verify_npm:-?})"
  fi

  echo "==> Pi ${PI_PACKAGE}@${PI_VERSION} instalado desde tarball verificado en $(command -v pi)"
}

install_repo_npm_tooling() {
  echo "==> Instalando dependencias npm del repositorio (CodeGraph, Repomix, OpenSpec)"
  hash -r
  local node_path npm_path node_ver
  node_path="$(command -v node || true)"
  npm_path="$(command -v npm || true)"
  node_ver="$(node --version 2>/dev/null || true)"
  if [ "$node_ver" != "$NODE_VERSION" ]; then
    cloud_tools_fail "npm ci requiere Node ${NODE_VERSION}; se encontró ${node_ver:-ninguno} (${node_path:-sin node})"
  fi
  if [ "$node_path" = "/exec-daemon/node" ] || [ "$npm_path" = "/exec-daemon/npm" ]; then
    cloud_tools_fail "npm ci no debe usar /exec-daemon/node"
  fi
  if [ -z "$npm_path" ]; then
    cloud_tools_fail "npm no está en PATH para npm ci"
  fi
  npm ci
  echo "==> npm ci completado con ${node_path} ${node_ver}"
}

install_cloud_agent_tools() {
  echo "==> Instalando herramientas fijadas de Cloud Agents (Node ${NODE_VERSION}, Gentle AI ${GENTLE_AI_VERSION}, Engram ${ENGRAM_VERSION}, Pi ${PI_VERSION})"

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

  install_pinned_nodejs

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
  install_pinned_pi
  echo "==> Binarios Cloud: $(command -v gentle-ai) $(command -v engram) $(command -v pi)"
  install_repo_npm_tooling
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

# Sourced by the isolated version-match test; do not install.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

if [ "${1:-}" = "--cloud-tools-only" ]; then
  install_cloud_agent_tools
  echo "==> Setup de herramientas Cloud completado."
  exit 0
fi

install_application_runtime
install_cloud_agent_tools

echo "==> Setup completado."
