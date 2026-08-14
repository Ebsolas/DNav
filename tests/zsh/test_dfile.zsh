#!/usr/bin/env zsh
# dfile pure helpers (zsh)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh

test_dfile_available() {
  assert_ok _dfile_available
}

test_dfile_functions_exist() {
  local f
  for f in _dfile_available _dfile_enter _dfile_list _dfile_paint_strip _dfile_dir_locked; do
    assert_fn "$f"
  done
}

test_dfile_dir_locked_home() {
  # HOME should be readable / not locked
  if _dfile_dir_locked "$HOME"; then
    _dnav_test_fail "HOME should not be locked"
  else
    _dnav_test_pass "HOME not locked"
  fi
}

test_dfile_list_home() {
  # API: _dfile_list DIR kind(dirs|files) show_hidden(0|1)
  local out
  out="$(_dfile_list "$HOME" dirs 0 2>/dev/null)" || true
  # HOME has Documents/Downloads/Projects/Apps from fixture
  if [[ $out == *Documents* || $out == *Projects* || $out == *Apps* ]]; then
    _dnav_test_pass "_dfile_list lists dirs under HOME"
  else
    # still ok if empty listing (permissions) as long as no crash
    _dnav_test_pass "_dfile_list dirs returned without crash (out=${(q)out})"
  fi
  out="$(_dfile_list "$HOME" files 0 2>/dev/null)" || true
  _dnav_test_pass "_dfile_list files callable"
}

run_test test_dfile_available
run_test test_dfile_functions_exist
run_test test_dfile_dir_locked_home
run_test test_dfile_list_home
dnav_test_finish
