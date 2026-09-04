#!/usr/bin/env bash
# Isolated checks for cloud_tools_version_matches. Uses mock CLIs under mktemp.
# Does not install binaries or touch /usr/local.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=.cursor/install.sh
source "${ROOT}/.cursor/install.sh"

pass=0
fail=0

run_case() {
  local label="$1"
  local printed="$2"
  local expected="$3"
  local want="$4"
  local tmpdir bin actual
  tmpdir="$(mktemp -d)"
  bin="${tmpdir}/tool"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$printed" > "$bin"
  chmod +x "$bin"
  if cloud_tools_version_matches "$bin" "$expected"; then
    actual="MATCH"
  else
    actual="NO MATCH"
  fi
  rm -rf "$tmpdir"
  if [ "$actual" = "$want" ]; then
    echo "PASS  ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL  ${label} (got ${actual}, want ${want})" >&2
    fail=$((fail + 1))
  fi
}

run_case "Node v22.23.2 expected 22.23.2" "v22.23.2" "22.23.2" "MATCH"
run_case "Node v22.23.20 expected 22.23.2" "v22.23.20" "22.23.2" "NO MATCH"
run_case "Engram 1.20.0 expected 1.20.0" "Engram 1.20.0" "1.20.0" "MATCH"
run_case "Engram 1.20.0-rc.1 expected 1.20.0" "Engram 1.20.0-rc.1" "1.20.0" "NO MATCH"
run_case "Gentle AI 2.5.0 expected 2.5.0" "Gentle AI 2.5.0" "2.5.0" "MATCH"
run_case "Gentle AI 2.5.0-rc.1 expected 2.5.0" "Gentle AI 2.5.0-rc.1" "2.5.0" "NO MATCH"
run_case "Pi 0.84.4 expected 0.84.4" "0.84.4" "0.84.4" "MATCH"
run_case "Pi v0.84.4 expected 0.84.4" "v0.84.4" "0.84.4" "MATCH"
run_case "Pi 0.84.40 expected 0.84.4" "0.84.40" "0.84.4" "NO MATCH"
run_case "Pi 0.84.4-rc.1 expected 0.84.4" "0.84.4-rc.1" "0.84.4" "NO MATCH"

echo "cloud_tools_version_matches: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
