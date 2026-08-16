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

test_winch_helpers_exist() {
  assert_fn _dnav_sync_term_size
  assert_fn _dnav_handle_winch
  assert_fn _dnav_maybe_resize
  assert_fn _dnav_read_key
  assert_fn _dnav_read_token
  assert_fn _dnav_paint_strip
  assert_fn _dnav_window
  assert_fn _dnav_finish
  assert_fn _dnav_usable_cols
  assert_fn _dnav_usable_from
  assert_fn _dnav_autowrap_off
  assert_fn _dnav_autowrap_on
  assert_fn _dnav_resize_chip_label
  assert_fn _dnav_tui_below
  _dnav_sync_term_size
  _dnav_test_pass "sync_term_size callable"
}

test_resize_waits_for_steady_stty() {
  assert_ge "$_DNAV_STEADY_NEED" 4 "several identical stty samples before restore"
}

test_resize_chip_label_main() {
  _DSEARCH_OPEN=0
  _DFILE_OPEN=0
  mode=main
  DNAV_CFG_BRAND=DNav
  assert_eq "$(_dnav_resize_chip_label)" " DNav " "main chip"
  assert_eq "$(_dnav_tui_below)" "0" "main has no extra rows"
}

test_resize_chip_label_search() {
  _DSEARCH_OPEN=1
  _dsearch_extra_lines=7
  assert_eq "$(_dnav_resize_chip_label)" " DNav Search:" "search chip"
  assert_eq "$(_dnav_tui_below)" "7" "search extra rows"
  _DSEARCH_OPEN=0
  _dsearch_extra_lines=0
}

test_usable_from_spares_two() {
  assert_eq "$(_dnav_usable_from 80)" "78" "80 → 78"
  assert_eq "$(_dnav_usable_from 10)" "8" "10 → 8"
  assert_eq "$(_dnav_usable_from 8)" "8" "floor 8"
}

test_public_commands_defined() {
  assert_fn dnav
  assert_fn dhelp
  assert_fn dconfig
  assert_fn _dnav_update
  assert_fn djump
  assert_fn _djump_add
  assert_fn _dsearch_start
  assert_fn _dfile_enter
  if (( $+functions[dupdate] )); then
    _dnav_test_fail "dupdate should be gone (use dnav --update)"
  else
    _dnav_test_pass "no dupdate command"
  fi
  if (( $+functions[dfavorite] )); then
    _dnav_test_fail "dfavorite should be gone (use djump add)"
  else
    _dnav_test_pass "no dfavorite command"
  fi
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

test_update_repo_finds_source() {
  local got
  got="$(_dnav_update_repo)"
  assert_file "$got/zsh/dnav" "dnav --update locates repo with zsh/dnav"
  got="$(DNAV_UPDATE_FROM="$DNAV_REPO_ROOT" _dnav_update_repo)"
  assert_eq "${got:A}" "${DNAV_REPO_ROOT:A}" "DNAV_UPDATE_FROM wins"
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
run_test test_winch_helpers_exist
run_test test_resize_waits_for_steady_stty
run_test test_resize_chip_label_main
run_test test_resize_chip_label_search
run_test test_usable_from_spares_two
run_test test_public_commands_defined
run_test test_dnav_dir_points_at_package
run_test test_config_dir_isolated
run_test test_update_repo_finds_source
run_test test_syntax_zsh_scripts
dnav_test_finish
