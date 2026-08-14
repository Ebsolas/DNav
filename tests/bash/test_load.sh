#!/usr/bin/env bash
# Module load + public command surface
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/bash_env.sh
source "$ROOT/tests/lib/bash_env.sh"

dnav_test_setup_bash

test_modules_available() {
  assert_ok _dnav_config_dir
  assert_ok _djump_available
  assert_ok _dsearch_available
  assert_ok _dfile_available
}

test_public_commands_defined() {
  assert_ok declare -f dnav
  assert_ok declare -f dhelp
  assert_ok declare -f dconfig
  assert_ok declare -f djump
  assert_ok declare -f dfavorite
  assert_ok declare -f _dsearch_start
  assert_ok declare -f _dfile_enter
}

test_dnav_dir_points_at_package() {
  assert_eq "$DNAV_DIR" "$DNAV_BASH_DIR" "DNAV_DIR is bash package"
  assert_file "$DNAV_DIR/dnav"
  assert_file "$DNAV_DIR/dsearch"
  assert_file "$DNAV_DIR/djump"
  assert_file "$DNAV_DIR/dfile"
}

test_config_dir_isolated() {
  local got
  got="$(_dnav_config_dir)"
  got="${got%$'\n'}"
  assert_eq "$got" "$DNAV_TEST_CONFIG" "uses isolated DNAV_CONFIG_DIR"
  assert_file "$DNAV_TEST_CONFIG/config"
  assert_file "$DNAV_TEST_CONFIG/folders"
  assert_file "$DNAV_TEST_CONFIG/jumps"
}

test_syntax_bash_scripts() {
  local f
  for f in dnav dfile djump dsearch; do
    assert_ok bash -n "$DNAV_BASH_DIR/$f"
  done
}

run_test test_modules_available
run_test test_public_commands_defined
run_test test_dnav_dir_points_at_package
run_test test_config_dir_isolated
run_test test_syntax_bash_scripts
dnav_test_finish
