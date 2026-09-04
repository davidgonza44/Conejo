#!/usr/bin/env bash
# Isolated Phase-1 Pi contract checks. Uses mocks under mktemp.
# Does not install binaries, touch /usr/local, or run npm pack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=.cursor/install.sh
source "${ROOT}/.cursor/install.sh"

pass=0
fail=0
REAL_HOME="${HOME:-}"

record() {
  local label="$1"
  local actual="$2"
  local want="$3"
  if [ "$actual" = "$want" ]; then
    echo "PASS  ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL  ${label} (got ${actual}, want ${want})" >&2
    fail=$((fail + 1))
  fi
}

pinned_node() {
  local prefix_node="/usr/local/lib/nodejs/node-${NODE_VERSION}/bin/node"
  if [ -x "$prefix_node" ]; then
    printf '%s' "$prefix_node"
    return 0
  fi
  if command -v node >/dev/null 2>&1 && [ "$(node --version 2>/dev/null || true)" = "$NODE_VERSION" ]; then
    command -v node
    return 0
  fi
  return 1
}

# --- Finding 1: flag-only version probe + isolated HOME ---

write_mock_node_cli() {
  local node_bin="$1"
  local cli="$2"
  local log="$3"
  local printed="${4-0.84.4}"
  local rc="${5-0}"
  mkdir -p "$(dirname "$cli")"
  printf 'fake-pi-cli\n' > "$cli"
  cat > "$node_bin" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
if [ "\$2" = "--version" ]; then
  printf '%s\n' "${printed}"
  exit ${rc}
fi
exit 1
EOF
  chmod +x "$node_bin"
}

finding1_only_version_flag() {
  local tmpdir node_bin cli log
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  log="${tmpdir}/argv.log"
  write_mock_node_cli "$node_bin" "$cli" "$log"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    if [ "$(cat "$log")" = "${cli} --version" ]; then
      record "Pi probe invokes pinned Node + CLI --version" "PASS" "PASS"
    else
      record "Pi probe invokes pinned Node + CLI --version" "argv=$(tr '\n' ' ' < "$log")" "${cli} --version"
    fi
  else
    record "Pi probe invokes pinned Node + CLI --version" "NO MATCH" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding1_generic_helper_still_tries_version() {
  local tmpdir bin log
  tmpdir="$(mktemp -d)"
  bin="${tmpdir}/tool"
  log="${tmpdir}/argv.log"
  cat > "$bin" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
printf '%s\n' "2.5.0"
EOF
  chmod +x "$bin"
  cloud_tools_version_matches "$bin" "2.5.0" >/dev/null || true
  if grep -qx -- 'version' "$log" && ! grep -qx -- '--version' "$log"; then
    record "generic helper still tries bare version first" "PASS" "PASS"
  else
    record "generic helper still tries bare version first" "argv=$(tr '\n' ' ' < "$log")" "version"
  fi
  rm -rf "$tmpdir"
}

finding1_home_isolation() {
  local tmpdir node_bin cli homelog marker
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  homelog="${tmpdir}/home.log"
  marker="pi-phase1-probe-marker-$$"
  rm -f "${REAL_HOME}/${marker}"
  printf 'fake-pi-cli\n' > "$cli"
  cat > "$node_bin" <<EOF
#!/bin/sh
printf '%s\n' "\$HOME" > "$homelog"
printf 'x\n' > "\$HOME/${marker}"
printf '%s\n' "0.84.4"
EOF
  chmod +x "$node_bin"
  cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4" >/dev/null || true
  if [ -e "${REAL_HOME}/${marker}" ]; then
    record "Pi probe isolates HOME" "wrote real HOME" "isolated"
  elif [ ! -s "$homelog" ]; then
    record "Pi probe isolates HOME" "no HOME log" "isolated"
  elif [ "$(cat "$homelog")" = "$REAL_HOME" ]; then
    record "Pi probe isolates HOME" "used real HOME" "isolated"
  else
    record "Pi probe isolates HOME" "PASS" "PASS"
  fi
  rm -f "${REAL_HOME}/${marker}"
  rm -rf "$tmpdir"
}

finding1_token_cases() {
  local tmpdir node_bin cli log
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  log="${tmpdir}/argv.log"
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.4"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "Pi --version 0.84.4 matches" "PASS" "PASS"
  else
    record "Pi --version 0.84.4 matches" "NO MATCH" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.40"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "Pi --version 0.84.40 rejected" "MATCH" "NO MATCH"
  else
    record "Pi --version 0.84.40 rejected" "PASS" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.4-rc.1"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "Pi --version 0.84.4-rc.1 rejected" "MATCH" "NO MATCH"
  else
    record "Pi --version 0.84.4-rc.1 rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

# --- Finding 2: PATH / binary invariant ---

finding2_empty_path() {
  local tmpdir prefix_pi
  tmpdir="$(mktemp -d)"
  prefix_pi="${tmpdir}/missing/pi"
  if (
    PATH="/nonexistent-pi-phase1-$$"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/missing" "$prefix_pi"
  ); then
    record "empty PATH fails closed" "PASS" "FAIL"
  else
    record "empty PATH fails closed" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding2_uncontrolled_binary() {
  local tmpdir prefix_pi other
  tmpdir="$(mktemp -d)"
  prefix_pi="${tmpdir}/prefix/pi"
  other="${tmpdir}/other/pi"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$other")"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$prefix_pi"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$other"
  chmod +x "$prefix_pi" "$other"
  if (
    PATH="$(dirname "$other"):/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/prefix" "$prefix_pi"
  ); then
    record "uncontrolled PATH pi fails closed" "PASS" "FAIL"
  else
    record "uncontrolled PATH pi fails closed" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding2_temp_exec_daemon_first() {
  local tmpdir prefix_pi daemon_pi
  tmpdir="$(mktemp -d)"
  prefix_pi="${tmpdir}/prefix/pi"
  daemon_pi="${tmpdir}/exec-daemon/pi"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$daemon_pi")"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$prefix_pi"
  printf '#!/bin/sh\nprintf "evil\\n"\n' > "$daemon_pi"
  chmod +x "$prefix_pi" "$daemon_pi"
  if (
    PATH="$(dirname "$daemon_pi"):$(dirname "$prefix_pi")"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/prefix" "$prefix_pi"
  ); then
    record "temp exec-daemon/pi first on PATH fails" "PASS" "FAIL"
  else
    record "temp exec-daemon/pi first on PATH fails" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding2_hidden_exec_daemon_symlink() {
  local tmpdir prefix_pi cargo_bin daemon_pi
  tmpdir="$(mktemp -d)"
  prefix_pi="${tmpdir}/prefix/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  daemon_pi="${tmpdir}/exec-daemon/pi"
  mkdir -p "$(dirname "$prefix_pi")" "$cargo_bin" "$(dirname "$daemon_pi")"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$prefix_pi"
  printf '#!/bin/sh\nprintf "evil\\n"\n' > "$daemon_pi"
  chmod +x "$prefix_pi" "$daemon_pi"
  ln -sfn "$daemon_pi" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/prefix" "$prefix_pi"
  ); then
    record "hidden exec-daemon symlink target rejected" "PASS" "FAIL"
  else
    record "hidden exec-daemon symlink target rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding2_controlled_symlink_chain() {
  local tmpdir prefix_pi dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix_pi="${tmpdir}/prefix/bin/pi"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$dest")" "$cargo_bin"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$prefix_pi"
  chmod +x "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/prefix" "$prefix_pi"
  ); then
    record "controlled cargo->dest->prefix chain accepted" "PASS" "PASS"
  else
    record "controlled cargo->dest->prefix chain accepted" "FAIL" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding2_dest_only_without_prefix() {
  local tmpdir dest prefix_pi
  tmpdir="$(mktemp -d)"
  dest="${tmpdir}/dest/pi"
  prefix_pi="${tmpdir}/prefix/bin/pi"
  mkdir -p "$(dirname "$dest")"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$dest"
  chmod +x "$dest"
  if (
    PATH="$(dirname "$dest"):/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "${tmpdir}/prefix" "$prefix_pi"
  ); then
    record "dest-only reuse without prefix_pi fails" "PASS" "FAIL"
  else
    record "dest-only reuse without prefix_pi fails" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

# --- Finding 3: exact --check argc; invalid calls never invoke Pi ---

run_wrapper() {
  local mock_bin="$1"
  shift
  PATH="${mock_bin}:${PATH}" hash -r
  PATH="${mock_bin}:${PATH}" "${ROOT}/.cursor/pi-review.sh" "$@"
}

finding3_invalid_wrapper_calls() {
  local tmpdir mock_bin log rc
  tmpdir="$(mktemp -d)"
  mock_bin="${tmpdir}/bin"
  log="${tmpdir}/pi.log"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/pi" <<EOF
#!/bin/sh
printf 'INVOKED %s\n' "\$*" >> "$log"
printf '%s\n' "0.84.4"
EOF
  chmod +x "${mock_bin}/pi"

  rc=0
  run_wrapper "$mock_bin" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$log" ]; then
    record "wrapper zero args exits 2 without Pi" "PASS" "PASS"
  else
    record "wrapper zero args exits 2 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "2/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" foo >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$log" ]; then
    record "wrapper foo exits 2 without Pi" "PASS" "PASS"
  else
    record "wrapper foo exits 2 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "2/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" --check extra >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$log" ]; then
    record "wrapper --check extra exits 2 without Pi" "PASS" "PASS"
  else
    record "wrapper --check extra exits 2 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "2/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" --check "prompt" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$log" ]; then
    record "wrapper --check prompt exits 2 without Pi" "PASS" "PASS"
  else
    record "wrapper --check prompt exits 2 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "2/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" --help >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && [ ! -s "$log" ]; then
    record "wrapper --help exits 0 without Pi" "PASS" "PASS"
  else
    record "wrapper --help exits 0 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "0/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" -h >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && [ ! -s "$log" ]; then
    record "wrapper -h exits 0 without Pi" "PASS" "PASS"
  else
    record "wrapper -h exits 0 without Pi" "rc=${rc} log=$(cat "$log" 2>/dev/null || true)" "0/empty"
  fi

  : > "$log"
  rc=0
  run_wrapper "$mock_bin" --check >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    record "wrapper --check rejects prepended mock Pi" "ok" "fail"
  elif [ -s "$log" ]; then
    record "wrapper --check rejects prepended mock Pi" "probed: $(cat "$log")" "empty"
  else
    record "wrapper --check rejects prepended mock Pi" "PASS" "PASS"
  fi

  rm -rf "$tmpdir"
}

# --- Finding 4: SRI bind + tarball-only install ---

finding4_known_sri() {
  local tmpdir file node_bin actual
  node_bin="$(pinned_node)" || {
    record "known SHA-512 SRI via pinned Node" "no node ${NODE_VERSION}" "present"
    return 0
  }
  tmpdir="$(mktemp -d)"
  file="${tmpdir}/hello.txt"
  printf 'hello\n' > "$file"
  actual="$(cloud_tools_sha512_sri "$file" "$node_bin")"
  if [ "$actual" = "sha512-58IrmUxZ2c8rSOVJseJGZmNgRZMNPafBrLKZ0cO3+TH5Sq5B7dosKyB6NuEPi8uNRSI+VIePWzFufOO2vAGWKQ==" ]; then
    record "known SHA-512 SRI via pinned Node" "PASS" "PASS"
  else
    record "known SHA-512 SRI via pinned Node" "$actual" "sha512-58Irm..."
  fi
  rm -rf "$tmpdir"
}

finding4_sri_mismatch() {
  local tmpdir file node_bin actual
  node_bin="$(pinned_node)" || {
    record "SRI mismatch rejected" "no node ${NODE_VERSION}" "present"
    return 0
  }
  tmpdir="$(mktemp -d)"
  file="${tmpdir}/not-pi.tgz"
  printf 'not-the-pi-tarball\n' > "$file"
  actual="$(cloud_tools_sha512_sri "$file" "$node_bin")"
  if [ "$actual" != "$PI_NPM_INTEGRITY" ]; then
    record "SRI mismatch rejected" "PASS" "PASS"
  else
    record "SRI mismatch rejected" "matched PI_NPM_INTEGRITY" "mismatch"
  fi
  rm -rf "$tmpdir"
}

finding4_install_rejects_registry_specs() {
  local tmpdir node_bin npm_cli prefix log
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  npm_cli="${tmpdir}/npm-cli.js"
  prefix="${tmpdir}/prefix"
  log="${tmpdir}/npm.log"
  mkdir -p "$prefix"
  printf 'fake-cli\n' > "$npm_cli"
  cat > "$node_bin" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
exit 0
EOF
  chmod +x "$node_bin"

  : > "$log"
  if (cloud_tools_pi_install_verified_tarball "$node_bin" "$npm_cli" "$prefix" "@earendil-works/pi-coding-agent@0.84.4"); then
    record "install rejects package-name spec" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "install rejects package-name spec" "npm ran: $(cat "$log")" "no npm"
  else
    record "install rejects package-name spec" "PASS" "PASS"
  fi

  : > "$log"
  if (cloud_tools_pi_install_verified_tarball "$node_bin" "$npm_cli" "$prefix" "latest"); then
    record "install rejects latest" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "install rejects latest" "npm ran: $(cat "$log")" "no npm"
  else
    record "install rejects latest" "PASS" "PASS"
  fi

  : > "$log"
  if (cloud_tools_pi_install_verified_tarball "$node_bin" "$npm_cli" "$prefix" "${tmpdir}/missing.tgz"); then
    record "install rejects missing tarball" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "install rejects missing tarball" "npm ran: $(cat "$log")" "no npm"
  else
    record "install rejects missing tarball" "PASS" "PASS"
  fi

  rm -rf "$tmpdir"
}

write_mock_pi() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  printf '#!/bin/sh\nprintf "0.84.4\\n"\n' > "$dest"
  chmod +x "$dest"
}

finding5_legitimate_npm_layout() {
  local tmpdir prefix prefix_pi cli dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/prefix"
  prefix_pi="${prefix}/bin/pi"
  cli="${prefix}/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  mkdir -p "$(dirname "$cli")" "$(dirname "$prefix_pi")" "$(dirname "$dest")" "$cargo_bin"
  write_mock_pi "$cli"
  ln -sfn "$cli" "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  ); then
    record "legitimate npm target beneath prefix accepted" "PASS" "PASS"
  else
    record "legitimate npm target beneath prefix accepted" "FAIL" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding5_escaped_tmp_target() {
  local tmpdir prefix prefix_pi outside dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/prefix"
  prefix_pi="${prefix}/bin/pi"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  outside="$(mktemp -p /tmp pi-escape.XXXXXX)"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$dest")" "$cargo_bin"
  write_mock_pi "$outside"
  ln -sfn "$outside" "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  ); then
    record "escaped /tmp target rejected" "PASS" "FAIL"
  else
    record "escaped /tmp target rejected" "PASS" "PASS"
  fi
  rm -f "$outside"
  rm -rf "$tmpdir"
}

finding5_escaped_exec_daemon_like() {
  local tmpdir prefix prefix_pi daemon_pi dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/prefix"
  prefix_pi="${prefix}/bin/pi"
  daemon_pi="${tmpdir}/exec-daemon/pi"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$daemon_pi")" "$(dirname "$dest")" "$cargo_bin"
  write_mock_pi "$daemon_pi"
  ln -sfn "$daemon_pi" "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  ); then
    record "escaped exec-daemon-like target rejected" "PASS" "FAIL"
  else
    record "escaped exec-daemon-like target rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding5_prefix_lookalike() {
  local tmpdir prefix prefix_pi lookalike dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/trusted/prefix"
  lookalike="${tmpdir}/trusted/prefix-evil/cli.js"
  prefix_pi="${prefix}/bin/pi"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$lookalike")" "$(dirname "$dest")" "$cargo_bin"
  write_mock_pi "$lookalike"
  ln -sfn "$lookalike" "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  ); then
    record "prefix-lookalike sibling target rejected" "PASS" "FAIL"
  else
    record "prefix-lookalike sibling target rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding5_path_and_prefix_agree_externally() {
  local tmpdir prefix prefix_pi outside dest cargo_bin
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/prefix"
  prefix_pi="${prefix}/bin/pi"
  dest="${tmpdir}/usr/local/bin/pi"
  cargo_bin="${tmpdir}/cargo/bin"
  outside="$(mktemp -p /tmp pi-agree.XXXXXX)"
  mkdir -p "$(dirname "$prefix_pi")" "$(dirname "$dest")" "$cargo_bin"
  write_mock_pi "$outside"
  ln -sfn "$outside" "$prefix_pi"
  ln -sfn "$prefix_pi" "$dest"
  ln -sfn "$dest" "${cargo_bin}/pi"
  if (
    PATH="${cargo_bin}:/nonexistent"
    hash -r
    cloud_tools_assert_pinned_pi_on_path "$prefix" "$prefix_pi"
  ); then
    record "PATH and prefix_pi agreeing on external target rejected" "PASS" "FAIL"
  else
    record "PATH and prefix_pi agreeing on external target rejected" "PASS" "PASS"
  fi
  rm -f "$outside"
  rm -rf "$tmpdir"
}

finding5_escaped_prefix_not_probed() {
  local tmpdir prefix prefix_pi outside log
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/prefix"
  prefix_pi="${prefix}/bin/pi"
  outside="$(mktemp -p /tmp pi-noprobe.XXXXXX)"
  log="${tmpdir}/argv.log"
  mkdir -p "$(dirname "$prefix_pi")"
  cat > "$outside" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
printf '%s\n' "0.84.4"
EOF
  chmod +x "$outside"
  ln -sfn "$outside" "$prefix_pi"
  if (cloud_tools_pi_reuse_if_ready "$prefix" "$prefix_pi"); then
    record "reuse helper rejects escaped prefix_pi before --version" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "reuse helper rejects escaped prefix_pi before --version" "probed: $(cat "$log")" "empty"
  else
    record "reuse helper rejects escaped prefix_pi before --version" "PASS" "PASS"
  fi
  rm -f "$outside"
  rm -rf "$tmpdir"
}

list_repo_tgz() {
  find "$ROOT" -name '*.tgz' -print | sort
}

write_mock_node_npm_pack() {
  local dest="$1"
  local log="$2"
  cat > "$dest" <<EOF
#!/bin/sh
printf 'argv=%s\n' "\$*" >> "$log"
printf 'ignore=%s\n' "\${npm_config_ignore_scripts-}" >> "$log"
dest=""
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "--pack-destination" ]; then
    dest="\$arg"
  fi
  prev="\$arg"
done
printf 'dest=%s\n' "\$dest" >> "$log"
if [ -z "\$dest" ] || [ ! -d "\$dest" ]; then
  exit 1
fi
printf 'fake-tarball\n' > "\$dest/earendil-works-pi-coding-agent-0.84.4.tgz"
exit 0
EOF
  chmod +x "$dest"
}

assert_pack_contract() {
  local label="$1"
  local hostile_tmpdir="$2"
  local tmpdir mock_node npm_cli log pack_dir before after tgz argv ignore dest expected_argv stray
  tmpdir="$(mktemp -d)"
  mock_node="${tmpdir}/node"
  npm_cli="${tmpdir}/npm-cli.js"
  log="${tmpdir}/npm.log"
  printf 'fake-npm-cli\n' > "$npm_cli"
  write_mock_node_npm_pack "$mock_node" "$log"
  before="$(list_repo_tgz)"
  pack_dir="$(TMPDIR="$hostile_tmpdir" cloud_tools_pi_mktemp_pack_dir)"
  cloud_tools_pi_npm_pack "$mock_node" "$npm_cli" "$PI_PACKAGE" "$PI_VERSION" "$pack_dir"
  after="$(list_repo_tgz)"
  tgz="${pack_dir}/earendil-works-pi-coding-agent-0.84.4.tgz"
  argv="$(sed -n 's/^argv=//p' "$log")"
  ignore="$(sed -n 's/^ignore=//p' "$log")"
  dest="$(sed -n 's/^dest=//p' "$log")"
  expected_argv="${npm_cli} pack ${PI_PACKAGE}@${PI_VERSION} --pack-destination ${pack_dir}"
  stray="$(find "$tmpdir" -name '*.tgz' -print | sort || true)"
  if cloud_tools_repo_contains_path "$pack_dir"; then
    record "$label" "pack_dir in repo" "outside"
  elif [ "$before" != "$after" ]; then
    record "$label" "new repo tgz" "unchanged"
  elif [ -n "$stray" ]; then
    record "$label" "tgz outside pack_dir: ${stray}" "none"
  elif [ ! -f "$tgz" ]; then
    record "$label" "missing fake tgz at pack_dir" "present"
  elif cloud_tools_repo_contains_path "$tgz"; then
    record "$label" "tgz in repo" "outside"
  elif [ "$argv" != "$expected_argv" ]; then
    record "$label" "argv=${argv}" "${expected_argv}"
  elif [ "$dest" != "$pack_dir" ]; then
    record "$label" "dest=${dest}" "${pack_dir}"
  elif [ "$ignore" != "true" ]; then
    record "$label" "ignore=${ignore}" "true"
  else
    record "$label" "PASS" "PASS"
  fi
  rm -rf "$pack_dir" "$tmpdir"
}

finding6_pack_dir_ignores_hostile_tmpdir() {
  assert_pack_contract "TMPDIR=ROOT pack uses external --pack-destination" "$ROOT"
  assert_pack_contract "TMPDIR=ROOT/.cursor pack uses external --pack-destination" "${ROOT}/.cursor"
}

finding6_containment_guard() {
  local before after
  before="$(list_repo_tgz)"
  if (cloud_tools_assert_outside_repo "$ROOT"); then
    record "containment guard rejects repository ROOT" "PASS" "FAIL"
  else
    record "containment guard rejects repository ROOT" "PASS" "PASS"
  fi
  if (cloud_tools_assert_outside_repo "${ROOT}/.cursor"); then
    record "containment guard rejects repository subdirectory" "PASS" "FAIL"
  else
    record "containment guard rejects repository subdirectory" "PASS" "PASS"
  fi
  after="$(list_repo_tgz)"
  if [ "$before" = "$after" ]; then
    record "containment tests created no new repository tarball" "PASS" "PASS"
  else
    record "containment tests created no new repository tarball" "changed" "unchanged"
  fi
}

finding4_install_accepts_local_tgz() {
  local tmpdir node_bin npm_cli prefix log tgz
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  npm_cli="${tmpdir}/npm-cli.js"
  prefix="${tmpdir}/prefix"
  log="${tmpdir}/npm.log"
  tgz="${tmpdir}/earendil-works-pi-coding-agent-0.84.4.tgz"
  mkdir -p "$prefix"
  printf 'dummy-tarball\n' > "$tgz"
  printf 'fake-cli\n' > "$npm_cli"
  cat > "$node_bin" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
exit 0
EOF
  chmod +x "$node_bin"

  if ! cloud_tools_pi_install_verified_tarball "$node_bin" "$npm_cli" "$prefix" "$tgz"; then
    record "install accepts verified local .tgz via pinned Node + npm CLI" "FAIL" "PASS"
    rm -rf "$tmpdir"
    return 0
  fi
  if grep -F -- "$npm_cli" "$log" >/dev/null \
    && grep -F -- "$tgz" "$log" >/dev/null \
    && grep -F -- "--ignore-scripts" "$log" >/dev/null \
    && ! grep -F -- "@earendil-works/pi-coding-agent@0.84.4" "$log" >/dev/null \
    && ! grep -F -- "latest" "$log" >/dev/null; then
    record "install accepts verified local .tgz via pinned Node + npm CLI" "PASS" "PASS"
  else
    record "install accepts verified local .tgz via pinned Node + npm CLI" "argv=$(cat "$log")" "node+cli+tgz"
  fi
  rm -rf "$tmpdir"
}

finding4_verified_pack_handoff() {
  local tmpdir pack_dir prefix log node_bin npm_cli tgz sri
  node_bin="$(pinned_node)" || {
    record "verified pack handoff installs hashed tarball" "no node ${NODE_VERSION}" "present"
    return 0
  }
  tmpdir="$(mktemp -d)"
  pack_dir="${tmpdir}/pack"
  prefix="${tmpdir}/prefix"
  log="${tmpdir}/npm.log"
  mkdir -p "$pack_dir" "$prefix"
  tgz="${pack_dir}/earendil-works-pi-coding-agent-0.84.4.tgz"
  printf 'verified-handoff-tarball\n' > "$tgz"
  npm_cli="${tmpdir}/npm-cli.js"
  cat > "$npm_cli" <<EOF
const fs = require("fs");
fs.appendFileSync("$log", process.argv.slice(2).join(" ") + "\n");
EOF
  sri="$(cloud_tools_sha512_sri "$tgz" "$node_bin")"
  : > "$log"
  if ! (cloud_tools_pi_install_verified_pack "$node_bin" "$npm_cli" "$prefix" "$pack_dir" "$sri"); then
    record "verified pack handoff installs hashed tarball" "FAIL" "PASS"
    rm -rf "$tmpdir"
    return 0
  fi
  if grep -Fx -- "install -g --prefix ${prefix} --ignore-scripts ${tgz}" "$log" >/dev/null \
    && ! grep -F -- "@earendil-works/pi-coding-agent@" "$log" >/dev/null \
    && ! grep -F -- "latest" "$log" >/dev/null; then
    record "verified pack handoff installs hashed tarball" "PASS" "PASS"
  else
    record "verified pack handoff installs hashed tarball" "argv=$(cat "$log")" "install ${tgz}"
  fi

  : > "$log"
  if (cloud_tools_pi_install_verified_pack "$node_bin" "$npm_cli" "$prefix" "$pack_dir" "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="); then
    record "verified pack handoff rejects SRI mismatch" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "verified pack handoff rejects SRI mismatch" "npm ran: $(cat "$log")" "no npm"
  else
    record "verified pack handoff rejects SRI mismatch" "PASS" "PASS"
  fi

  printf 'second\n' > "${pack_dir}/second.tgz"
  : > "$log"
  if (cloud_tools_pi_install_verified_pack "$node_bin" "$npm_cli" "$prefix" "$pack_dir" "$sri"); then
    record "verified pack handoff rejects multiple candidates" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "verified pack handoff rejects multiple candidates" "npm ran: $(cat "$log")" "no npm"
  else
    record "verified pack handoff rejects multiple candidates" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding1_only_version_flag
finding1_generic_helper_still_tries_version
finding1_home_isolation
finding1_token_cases
finding2_empty_path
finding2_uncontrolled_binary
finding2_temp_exec_daemon_first
finding2_hidden_exec_daemon_symlink
finding2_controlled_symlink_chain
finding2_dest_only_without_prefix
finding3_invalid_wrapper_calls
finding7_version_exit_status() {
  local tmpdir node_bin cli log
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  log="${tmpdir}/argv.log"
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.4" "0"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "helper 0.84.4 exit 0 matches" "PASS" "PASS"
  else
    record "helper 0.84.4 exit 0 matches" "NO MATCH" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.4" "42"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "helper 0.84.4 exit 42 rejected" "MATCH" "NO MATCH"
  else
    record "helper 0.84.4 exit 42 rejected" "PASS" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "0.84.40" "0"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "helper 0.84.40 exit 0 rejected" "MATCH" "NO MATCH"
  else
    record "helper 0.84.40 exit 0 rejected" "PASS" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "" "0"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "helper empty exit 0 rejected" "MATCH" "NO MATCH"
  else
    record "helper empty exit 0 rejected" "PASS" "PASS"
  fi
  write_mock_node_cli "$node_bin" "$cli" "$log" "" "42"
  if cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"; then
    record "helper empty exit 42 rejected" "MATCH" "NO MATCH"
  else
    record "helper empty exit 42 rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding7_wrapper_exit_status() {
  local tmpdir mock_bin log rc
  tmpdir="$(mktemp -d)"
  mock_bin="${tmpdir}/bin"
  log="${tmpdir}/pi.log"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/pi" <<EOF
#!/bin/sh
printf 'INVOKED %s\n' "\$*" >> "$log"
printf '%s\n' "0.84.4"
exit 42
EOF
  chmod +x "${mock_bin}/pi"
  rc=0
  run_wrapper "$mock_bin" --check >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    record "malicious same-version Pi first on PATH is rejected" "ok" "fail"
  elif [ -s "$log" ]; then
    record "malicious same-version Pi first on PATH is rejected" "probed: $(cat "$log")" "empty"
  else
    record "malicious same-version Pi first on PATH is rejected" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding7_probe_home_hostile_tmpdir() {
  local tmpdir node_bin cli homelog
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  homelog="${tmpdir}/home.log"
  printf 'fake-pi-cli\n' > "$cli"
  cat > "$node_bin" <<EOF
#!/bin/sh
printf '%s\n' "\$HOME" > "$homelog"
mkdir -p "\$HOME/.pi/agent"
printf '{}\n' > "\$HOME/.pi/agent/auth.json"
printf '%s\n' "0.84.4"
EOF
  chmod +x "$node_bin"
  TMPDIR="$ROOT" cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4" >/dev/null || true
  if [ ! -s "$homelog" ]; then
    record "helper probe HOME ignores TMPDIR=ROOT" "no HOME" "outside"
  elif cloud_tools_repo_contains_path "$(cat "$homelog")"; then
    record "helper probe HOME ignores TMPDIR=ROOT" "$(cat "$homelog")" "outside"
  elif [ -e "${REAL_HOME}/.pi/agent/auth.json" ]; then
    record "helper probe HOME ignores TMPDIR=ROOT" "wrote real HOME" "isolated"
  else
    record "helper probe HOME ignores TMPDIR=ROOT" "PASS" "PASS"
  fi
  : > "$homelog"
  TMPDIR="${ROOT}/.cursor" cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4" >/dev/null || true
  if [ ! -s "$homelog" ]; then
    record "helper probe HOME ignores TMPDIR=ROOT/.cursor" "no HOME" "outside"
  elif cloud_tools_repo_contains_path "$(cat "$homelog")"; then
    record "helper probe HOME ignores TMPDIR=ROOT/.cursor" "$(cat "$homelog")" "outside"
  elif [ -e "${REAL_HOME}/.pi/agent/auth.json" ]; then
    record "helper probe HOME ignores TMPDIR=ROOT/.cursor" "wrote real HOME" "isolated"
  else
    record "helper probe HOME ignores TMPDIR=ROOT/.cursor" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding7_wrapper_probe_home_hostile_tmpdir() {
  local rc
  rc=0
  TMPDIR="$ROOT" "${ROOT}/.cursor/pi-review.sh" --check >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    record "wrapper probe HOME ignores TMPDIR=ROOT" "rc=$rc" "0"
  else
    record "wrapper probe HOME ignores TMPDIR=ROOT" "PASS" "PASS"
  fi
}

finding7_probe_home_failure_skips_pi() {
  local tmpdir node_bin cli log survived
  tmpdir="$(mktemp -d)"
  node_bin="${tmpdir}/node"
  cli="${tmpdir}/cli.js"
  log="${tmpdir}/argv.log"
  write_mock_node_cli "$node_bin" "$cli" "$log"
  # set +e so a mere return 1 would continue and print SURVIVED.
  # cloud_tools_fail must exit the subshell before that marker.
  survived="$(
    set +e
    cloud_tools_pi_mktemp_probe_home() { return 1; }
    cloud_tools_pi_version_matches "$node_bin" "$cli" "0.84.4"
    printf 'SURVIVED\n'
  )" || true
  if [ -s "$log" ]; then
    record "failed probe HOME never invokes Pi" "probed: $(cat "$log")" "empty"
  elif printf '%s\n' "$survived" | grep -qx SURVIVED; then
    record "failed probe HOME never invokes Pi" "continued after helper failure" "fail-closed exit"
  else
    record "failed probe HOME never invokes Pi" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding7_wrapper_probe_home_failure_skips_pi() {
  local tmpdir mock_bin err rc
  tmpdir="$(mktemp -d)"
  mock_bin="${tmpdir}/bin"
  err="${tmpdir}/err.log"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/mktemp" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${mock_bin}/mktemp"
  rc=0
  PATH="${mock_bin}:${PATH}" "${ROOT}/.cursor/pi-review.sh" --check >/dev/null 2>"$err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    record "wrapper failed probe HOME never invokes Pi" "ok" "fail"
  elif ! grep -Fq "no se pudo crear un HOME temporal seguro para Pi" "$err"; then
    record "wrapper failed probe HOME never invokes Pi" "err=$(tr '\n' ' ' < "$err")" "probe-home fail"
  else
    record "wrapper failed probe HOME never invokes Pi" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

write_ready_node_prefix() {
  local prefix="$1"
  local node_ver="${2-v22.23.2}"
  local npm_ver="${3-10.9.8}"
  local node_rc="${4-0}"
  local npm_rc="${5-0}"
  local log="${6-}"
  mkdir -p "${prefix}/bin" "${prefix}/lib/node_modules/npm/bin"
  cat > "${prefix}/bin/node" <<EOF
#!/bin/sh
if [ -n "${log}" ]; then
  printf 'INVOKED %s\n' "\$*" >> "${log}"
fi
if [ "\$1" = "--version" ]; then
  printf '%s\\n' "${node_ver}"
  exit ${node_rc}
fi
if [ "\$2" = "--version" ]; then
  printf '%s\\n' "${npm_ver}"
  exit ${npm_rc}
fi
exit 1
EOF
  chmod +x "${prefix}/bin/node"
  printf 'fake-npm-cli\n' > "${prefix}/lib/node_modules/npm/bin/npm-cli.js"
  chmod +x "${prefix}/lib/node_modules/npm/bin/npm-cli.js"
  ln -sfn "../lib/node_modules/npm/bin/npm-cli.js" "${prefix}/bin/npm"
}

finding8_nodejs_prefix_ready() {
  local tmpdir prefix outside
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/node-${NODE_VERSION}"
  write_ready_node_prefix "$prefix"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "correct pinned node + bundled npm 10.9.8" "PASS" "PASS"
  else
    record "correct pinned node + bundled npm 10.9.8" "NO" "PASS"
  fi

  rm -f "${prefix}/bin/npm"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "missing prefix/bin/npm" "PASS" "FAIL"
  else
    record "missing prefix/bin/npm" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix"
  rm -f "${prefix}/bin/npm" "${prefix}/lib/node_modules/npm/bin/npm-cli.js"
  printf '#!/bin/sh\nexit 0\n' > "${prefix}/bin/npm"
  chmod +x "${prefix}/bin/npm"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "prefix/bin/npm exists but bundled npm missing" "PASS" "FAIL"
  else
    record "prefix/bin/npm exists but bundled npm missing" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "v22.23.2" "9.9.9"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "bundled npm wrong version" "PASS" "FAIL"
  else
    record "bundled npm wrong version" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix"
  outside="$(mktemp -p /tmp npm-escape.XXXXXX)"
  printf 'evil-npm\n' > "$outside"
  ln -sfn "$outside" "${prefix}/bin/npm"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "prefix npm escaping outside prefix" "PASS" "FAIL"
  else
    record "prefix npm escaping outside prefix" "PASS" "PASS"
  fi
  rm -f "$outside"

  write_ready_node_prefix "$prefix" "v22.23.20" "10.9.8"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "wrong Node version inside prefix" "PASS" "FAIL"
  else
    record "wrong Node version inside prefix" "PASS" "PASS"
  fi

  if cloud_tools_pinned_nodejs_prefix_ready "${tmpdir}/missing-prefix"; then
    record "same-version system Node, prefix absent" "PASS" "FAIL"
  else
    record "same-version system Node, prefix absent" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "v22.23.2" "10.9.8" "42" "0"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "Node v22.23.2 exit 42" "PASS" "FAIL"
  else
    record "Node v22.23.2 exit 42" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "v22.23.2" "10.9.8" "0" "42"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "npm 10.9.8 exit 42" "PASS" "FAIL"
  else
    record "npm 10.9.8 exit 42" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "" "10.9.8" "0" "0"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "Node empty exit 0" "PASS" "FAIL"
  else
    record "Node empty exit 0" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "v22.23.2" "" "0" "0"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "npm empty exit 0" "PASS" "FAIL"
  else
    record "npm empty exit 0" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding8_node_rejected_before_exec() {
  local tmpdir prefix outside log
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/node-${NODE_VERSION}"
  outside="$(mktemp -d)"
  log="${tmpdir}/argv.log"

  write_ready_node_prefix "${outside}/real" "v22.23.2" "10.9.8" "0" "0" "$log"
  ln -sfn "${outside}/real" "$prefix"
  : > "$log"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "relocated prefix rejected before exec" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "relocated prefix rejected before exec" "probed: $(cat "$log")" "empty"
  else
    record "relocated prefix rejected before exec" "PASS" "PASS"
  fi

  rm -rf "$prefix"
  write_ready_node_prefix "$prefix" "v22.23.2" "10.9.8" "0" "0" "$log"
  cat > "${outside}/evil-node" <<EOF
#!/bin/sh
printf 'INVOKED %s\n' "\$*" >> "$log"
printf 'v22.23.2\n'
exit 0
EOF
  chmod +x "${outside}/evil-node"
  ln -sfn "${outside}/evil-node" "${prefix}/bin/node"
  : > "$log"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "prefix/bin/node external same-version rejected before exec" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "prefix/bin/node external same-version rejected before exec" "probed: $(cat "$log")" "empty"
  else
    record "prefix/bin/node external same-version rejected before exec" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix" "v22.23.2" "10.9.8" "0" "0" "$log"
  mv "${prefix}/bin/node" "${prefix}/lib/other-node"
  ln -sfn "../lib/other-node" "${prefix}/bin/node"
  : > "$log"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "prefix/bin/node alternate internal target rejected" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "prefix/bin/node alternate internal target rejected" "probed: $(cat "$log")" "empty"
  else
    record "prefix/bin/node alternate internal target rejected" "PASS" "PASS"
  fi

  write_ready_node_prefix "$prefix"
  ln -sfn "$outside" "${prefix}/lib/node_modules/npm/bin/npm-cli.js"
  : > "$log"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix"; then
    record "npm-cli.js external symlink rejected before exec" "PASS" "FAIL"
  else
    record "npm-cli.js external symlink rejected before exec" "PASS" "PASS"
  fi
  rm -rf "$tmpdir" "$outside"
}

finding8_prefix_hardened_rejects_user_tree() {
  local tmpdir prefix
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/node-${NODE_VERSION}"
  write_ready_node_prefix "$prefix"
  if cloud_tools_pinned_nodejs_prefix_ready "$prefix" \
    && ! cloud_tools_pinned_nodejs_prefix_hardened "$prefix"; then
    record "user-owned prefix is ready but not hardened" "PASS" "PASS"
  else
    record "user-owned prefix is ready but not hardened" "unexpected" "ready+not-hardened"
  fi
  rm -rf "$tmpdir"
}

finding8_reuse_gate_probes_nothing_unhardened() {
  local tmpdir prefix log
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/node-${NODE_VERSION}"
  log="${tmpdir}/argv.log"
  : > "$log"
  write_ready_node_prefix "$prefix" "v22.23.2" "10.9.8" "0" "0" "$log"
  chmod 0777 "${prefix}/bin/node"
  if cloud_tools_pinned_nodejs_prefix_reusable "$prefix"; then
    record "reuse gate rejects writable prefix without probing" "PASS" "FAIL"
  elif [ -s "$log" ]; then
    record "reuse gate rejects writable prefix without probing" "probed: $(cat "$log")" "empty"
  else
    record "reuse gate rejects writable prefix without probing" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding8_hardened_rejects_scan_error() {
  local tmpdir prefix bindir old_path
  tmpdir="$(mktemp -d)"
  prefix="${tmpdir}/node-${NODE_VERSION}"
  write_ready_node_prefix "$prefix"
  bindir="${tmpdir}/fakebin"
  mkdir -p "$bindir"
  cat > "${bindir}/find" <<EOF
#!/bin/sh
echo "mock-find: Permission denied" >&2
exit 1
EOF
  chmod +x "${bindir}/find"
  old_path="$PATH"
  PATH="${bindir}:$PATH"
  if cloud_tools_pinned_nodejs_prefix_hardened "$prefix"; then
    PATH="$old_path"
    record "hardened rejects prefix on scan error" "PASS" "FAIL"
  else
    PATH="$old_path"
    record "hardened rejects prefix on scan error" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding8_wrapper_authenticates_prefix_before_exec() {
  local gate_line exec_line
  gate_line="$(grep -n 'pi_review_scan_clean' "${ROOT}/.cursor/pi-review.sh" | head -n 1 | cut -d: -f1)"
  exec_line="$(grep -nF '"$PI_PINNED_NODE" "$PI_PINNED_CLI" --version' "${ROOT}/.cursor/pi-review.sh" | head -n 1 | cut -d: -f1)"
  if [ -n "$gate_line" ] && [ -n "$exec_line" ] && [ "$gate_line" -lt "$exec_line" ]; then
    record "wrapper authenticates prefix metadata before Node exec" "PASS" "PASS"
  else
    record "wrapper authenticates prefix metadata before Node exec" "gate=${gate_line} exec=${exec_line}" "gate<exec"
  fi
}

finding8_pin_drift_node_prefix() {
  local encoded want cli_line install_pi wrapper_pi install_sri approved_sri
  encoded="$(sed -n 's/^PI_PINNED_NODE_PREFIX="\(.*\)"/\1/p' "${ROOT}/.cursor/pi-review.sh" | head -n 1)"
  want="/usr/local/lib/nodejs/node-${NODE_VERSION}"
  if [ "$encoded" = "$want" ]; then
    record "install.sh NODE_VERSION matches pi-review PI_PINNED_NODE_PREFIX" "PASS" "PASS"
  else
    record "install.sh NODE_VERSION matches pi-review PI_PINNED_NODE_PREFIX" "${encoded}" "${want}"
  fi
  cli_line="$(sed -n 's/^PI_PINNED_CLI="\(.*\)"/\1/p' "${ROOT}/.cursor/pi-review.sh" | head -n 1)"
  if printf '%s\n' "$cli_line" | grep -Fq 'dist/bundle/cli.js' \
    && printf '%s\n' "$cli_line" | grep -Fq 'PI_PINNED_NODE_PREFIX'; then
    record "Pi 0.84.4 CLI remains dist/bundle/cli.js" "PASS" "PASS"
  else
    record "Pi 0.84.4 CLI remains dist/bundle/cli.js" "${cli_line}" "PI_PINNED_NODE_PREFIX/.../dist/bundle/cli.js"
  fi
  install_pi="$(sed -n 's/^PI_VERSION="\(.*\)"/\1/p' "${ROOT}/.cursor/install.sh" | head -n 1)"
  wrapper_pi="$(sed -n 's/^PI_EXPECTED_VERSION="\(.*\)"/\1/p' "${ROOT}/.cursor/pi-review.sh" | head -n 1)"
  if [ -n "$install_pi" ] && [ "$install_pi" = "0.84.4" ]; then
    record "install.sh PI_VERSION is 0.84.4" "PASS" "PASS"
  else
    record "install.sh PI_VERSION is 0.84.4" "${install_pi}" "0.84.4"
  fi
  if [ -n "$wrapper_pi" ] && [ "$wrapper_pi" = "$install_pi" ]; then
    record "pi-review PI_EXPECTED_VERSION matches install.sh PI_VERSION" "PASS" "PASS"
  else
    record "pi-review PI_EXPECTED_VERSION matches install.sh PI_VERSION" "${wrapper_pi}" "${install_pi}"
  fi
  approved_sri="sha512-jmOlrqUmvhh/siNWFRXjYLJzhKFIHNsAQaysRwzQPQFnPAaV/vhqHsLH/MBsIISA1Rjj7WTUFR3nJrpXoLx39w=="
  install_sri="$(sed -n 's/^PI_NPM_INTEGRITY="\(.*\)"/\1/p' "${ROOT}/.cursor/install.sh" | head -n 1)"
  if [ -n "$install_sri" ] && [ "$install_sri" = "$approved_sri" ]; then
    record "PI_NPM_INTEGRITY is the approved SRI" "PASS" "PASS"
  else
    record "PI_NPM_INTEGRITY is the approved SRI" "${install_sri}" "${approved_sri}"
  fi
}

finding8_wrapper_accepts_pinned_pi() {
  local prefix prefix_pi resolved expected canonical_prefix output rc
  prefix="/usr/local/lib/nodejs/node-${NODE_VERSION}"
  prefix_pi="${prefix}/bin/pi"
  if [ ! -x "$prefix_pi" ]; then
    record "wrapper accepts controlled pinned Pi chain" "missing ${prefix_pi}" "present"
    return 0
  fi
  rc=0
  output="$("${ROOT}/.cursor/pi-review.sh" --check 2>&1)" || rc=$?
  resolved="$(/usr/bin/readlink -f "$(command -v pi)")" || resolved=""
  expected="$(/usr/bin/readlink -f "$prefix_pi")" || expected=""
  canonical_prefix="$(/usr/bin/readlink -f "$prefix")" || canonical_prefix=""
  if [ "$rc" -ne 0 ]; then
    record "wrapper accepts controlled pinned Pi chain" "rc=$rc" "0"
  elif ! printf '%s\n' "$output" | grep -Fq "pi-review check: ok"; then
    record "wrapper accepts controlled pinned Pi chain" "no ok" "ok"
  elif [ -z "$resolved" ] || [ "$resolved" != "$expected" ]; then
    record "wrapper accepts controlled pinned Pi chain" "${resolved}" "${expected}"
  elif ! cloud_tools_path_is_beneath "$resolved" "$canonical_prefix"; then
    record "wrapper accepts controlled pinned Pi chain" "${resolved} not under ${canonical_prefix}" "beneath"
  else
    record "wrapper accepts controlled pinned Pi chain" "PASS" "PASS"
  fi
}

finding4_known_sri
finding4_sri_mismatch
finding4_install_rejects_registry_specs
finding4_install_accepts_local_tgz
finding4_verified_pack_handoff
finding5_legitimate_npm_layout
finding5_escaped_tmp_target
finding5_escaped_exec_daemon_like
finding5_prefix_lookalike
finding5_path_and_prefix_agree_externally
finding5_escaped_prefix_not_probed
finding6_pack_dir_ignores_hostile_tmpdir
finding6_containment_guard
finding7_version_exit_status
finding7_wrapper_exit_status
finding7_probe_home_hostile_tmpdir
finding7_wrapper_probe_home_hostile_tmpdir
finding7_probe_home_failure_skips_pi
finding7_wrapper_probe_home_failure_skips_pi
finding9_wrapper_malicious_path_node() {
  local tmpdir mock_bin log rc output
  tmpdir="$(mktemp -d)"
  mock_bin="${tmpdir}/bin"
  log="${tmpdir}/node.log"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/node" <<EOF
#!/bin/sh
printf 'INVOKED %s\n' "\$*" >> "$log"
printf 'forged\n'
exit 0
EOF
  chmod +x "${mock_bin}/node"
  rc=0
  output="$(PATH="${mock_bin}:${PATH}" "${ROOT}/.cursor/pi-review.sh" --check 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    record "legitimate Pi + malicious PATH Node" "rc=$rc" "0"
  elif ! printf '%s\n' "$output" | grep -Fq "pi-review check: ok"; then
    record "legitimate Pi + malicious PATH Node" "no ok" "ok"
  elif [ -s "$log" ]; then
    record "legitimate Pi + malicious PATH Node" "probed: $(cat "$log")" "empty"
  else
    record "legitimate Pi + malicious PATH Node" "PASS" "PASS"
  fi
  rm -rf "$tmpdir"
}

finding9_repo_npm_ci_uses_pinned_paths() {
  if grep -nE '^\s+npm ci\s*$|^\s+node --version|^\s+npm --version' "${ROOT}/.cursor/install.sh" >/dev/null; then
    record "install.sh has no PATH npm ci / node --version" "present" "absent"
  elif grep -Fq '"$prefix_node" "$npm_cli" ci' "${ROOT}/.cursor/install.sh" \
    && grep -Fq '"$node_bin" "$npm_cli" pack' "${ROOT}/.cursor/install.sh" \
    && grep -Fq '"$node_bin" "$npm_cli" install' "${ROOT}/.cursor/install.sh" \
    && grep -Fq '"$PI_PINNED_NODE" "$PI_PINNED_CLI" --version' "${ROOT}/.cursor/pi-review.sh"; then
    record "pack/install/ci/wrapper use pinned Node + CLI" "PASS" "PASS"
  else
    record "pack/install/ci/wrapper use pinned Node + CLI" "missing invocation" "pinned"
  fi
}

finding8_nodejs_prefix_ready
finding8_node_rejected_before_exec
finding8_prefix_hardened_rejects_user_tree
finding8_reuse_gate_probes_nothing_unhardened
finding8_hardened_rejects_scan_error
finding8_wrapper_authenticates_prefix_before_exec
finding8_pin_drift_node_prefix
finding8_wrapper_accepts_pinned_pi
finding9_wrapper_malicious_path_node
finding9_repo_npm_ci_uses_pinned_paths

echo "pi phase1 contract: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
