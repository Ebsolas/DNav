#!/usr/bin/env zsh
# Module load + public command surface (zsh)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh

test_modules_available() {
  assert_ok _dnav_config_dir
  assert_ok _djump_available
  assert_ok _dsearch_available
  assert_ok _dfile_available
}

test_public_commands_defined() {
  assert_fn dnav
  assert_fn dhelp
  assert_fn dconfig
  assert_fn djump
  assert_fn dfavorite
  assert_fn _dsearch_start
  assert_fn _dfile_enter
}

test_dnav_dir_points_at_package() {
  # DNAV_DIR is set by zsh/dnav to package location
  assert_file "$DNAV_ZSH_DIR/dnav"
  assert_file "$DNAV_ZSH_DIR/dsearch"
  assert_file "$DNAV_ZSH_DIR/djump"
  assert_file "$DNAV_ZSH_DIR/dfile"
  if [[ -n ${DNAV_DIR:-} ]]; then
    assert_eq "${DNAV_DIR:A}" "${DNAV_ZSH_DIR:A}" "DNAV_DIR is zsh package"
  else
    _dnav_test_pass "DNAV_DIR optional on this build"
  fi
}

test_config_dir_isolated() {
  local got
  got="$(_dnav_config_dir)"
  assert_eq "$got" "$DNAV_TEST_CONFIG" "uses isolated DNAV_CONFIG_DIR"
  assert_file "$DNAV_TEST_CONFIG/config"
  assert_file "$DNAV_TEST_CONFIG/folders"
  assert_file "$DNAV_TEST_CONFIG/jumps"
}

test_syntax_zsh_scripts() {
  local f
  for f in dnav dfile djump dsearch; do
    if zsh -n "$DNAV_ZSH_DIR/$f" 2>/dev/null; then
      _dnav_test_pass "zsh -n $f"
    else
      _dnav_test_fail "zsh -n $f"
    fi
  done
}

run_test test_modules_available
run_test test_public_commands_defined
run_test test_dnav_dir_points_at_package
run_test test_config_dir_isolated
run_test test_syntax_zsh_scripts
dnav_test_finish
