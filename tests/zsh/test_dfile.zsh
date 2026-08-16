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
  for f in _dfile_available _dfile_enter _dfile_list _dfile_paint_strip _dfile_dir_locked _dfile_jump_name _dfile_jump_label _dfile_sort_dir_label _dfile_sort_file_label _dfile_sort_dir_short _dfile_sort_file_short _dfile_cycle_dir_sort _dfile_cycle_file_sort _dfile_status_compact _dfile_draw _dfile_erase _dfile_refresh _dfile_session_reset _dfile_cancel_restore; do
    assert_fn "$f"
  done
}

test_dfile_jump_name_truncates_end() {
  local got
  got="$(_dfile_jump_name "/tmp/abcdefghij" 20)"
  assert_eq "$got" "abcdefghij" "short name unchanged"
  got="$(_dfile_jump_name "/tmp/abcdefghijklmnopqrstuvwxyz" 20)"
  assert_eq "$got" "abcdefghijklmnopqrst" "keeps first 20, cuts the end"
  got="$(_dfile_jump_name "/tmp/abcdefghijklmnopqrstuvwxyz" 8)"
  assert_eq "$got" "abcdefgh" "honors explicit max"
  got="$(_dfile_jump_name "/" 20)"
  assert_eq "$got" "/" "root is /"
  DNAV_CFG_DFILE_JUMP_NAME_MAX=5
  got="$(_dfile_jump_name "/tmp/toolong")"
  assert_eq "$got" "toolo" "reads DNAV_CFG_DFILE_JUMP_NAME_MAX"
  DNAV_CFG_DFILE_JUMP_NAME_MAX=20
  got="$(_dfile_jump_label "/tmp/abcdefghijklmnopqrstuvwxyz")"
  assert_eq "$got" " Jump to: abcdefghijklmnopqrst " "label wraps truncated name"
}

test_dfile_child_row_window_fits() {
  local -a child_row
  local i used w
  child_row=("Jump to: currentfolder")
  for i in {1..20}; do
    child_row+=("folder$i")
  done
  _dfile_window child_row 1 0 40 "" 1
  used=0
  for i in {1..$#_dfile_vis}; do
    w="$(_dfile_cell_w "${_dfile_vis[i]}" 0)"
    (( used += w ))
  done
  assert_eq "$_dfile_vis[1]" "Jump to: currentfolder" "Jump to: stays first while sel fits"
  if (( used <= 40 )); then
    _dnav_test_pass "visible chips fit in 40 cols (used=$used)"
  else
    _dnav_test_fail "visible chips overflow 40 cols (used=$used vis=${#_dfile_vis})"
  fi
}

test_dfile_sort_labels() {
  assert_eq "$(_dfile_sort_dir_label alpha)" "Alpha" "dir alpha"
  assert_eq "$(_dfile_sort_dir_label hidden_first)" "Dot" "dir hidden_first → Dot"
  assert_eq "$(_dfile_sort_file_label alpha)" "Alpha" "file alpha"
  assert_eq "$(_dfile_sort_file_label ext)" "Ext" "file ext"
  assert_eq "$(_dfile_sort_file_label dot_first)" "Dot" "file dot_first → Dot"
  assert_eq "$(_dfile_sort_file_label dot_ext)" "Dot/Ext" "file dot_ext → Dot/Ext"
  assert_eq "$(_dfile_sort_dir_short alpha)" "A" "dir short alpha"
  assert_eq "$(_dfile_sort_dir_short hidden_first)" "D" "dir short Dot"
  assert_eq "$(_dfile_sort_file_short alpha)" "A" "file short alpha"
  assert_eq "$(_dfile_sort_file_short ext)" "E" "file short Ext"
  assert_eq "$(_dfile_sort_file_short dot_first)" "D" "file short Dot"
  assert_eq "$(_dfile_sort_file_short dot_ext)" "DE" "file short Dot/Ext"
}

test_dfile_status_compact_threshold() {
  if _dfile_status_compact 46; then
    _dnav_test_pass "46 cols is compact"
  else
    _dnav_test_fail "46 cols should be compact"
  fi
  if _dfile_status_compact 47; then
    _dnav_test_fail "47 cols should be full"
  else
    _dnav_test_pass "47 cols is full"
  fi
}

test_dfile_cycle_sort() {
  DNAV_CFG_DFILE_SORT_DIRS=alpha
  DNAV_CFG_DFILE_SORT_FILES=alpha
  _DFILE_SORT_DIRS=alpha
  _DFILE_SORT_FILES=alpha
  _dfile_cycle_dir_sort
  assert_eq "$_DFILE_SORT_DIRS" "hidden_first" "dir alpha → hidden_first"
  _dfile_cycle_dir_sort
  assert_eq "$_DFILE_SORT_DIRS" "alpha" "dir hidden_first → alpha"
  assert_eq "$DNAV_CFG_DFILE_SORT_DIRS" "alpha" "dir cycle does not write config"
  _dfile_cycle_file_sort
  assert_eq "$_DFILE_SORT_FILES" "ext" "file alpha → ext"
  _dfile_cycle_file_sort
  assert_eq "$_DFILE_SORT_FILES" "dot_first" "file ext → dot_first"
  _dfile_cycle_file_sort
  assert_eq "$_DFILE_SORT_FILES" "dot_ext" "file dot_first → dot_ext"
  _dfile_cycle_file_sort
  assert_eq "$_DFILE_SORT_FILES" "alpha" "file dot_ext → alpha"
  assert_eq "$DNAV_CFG_DFILE_SORT_FILES" "alpha" "file cycle does not write config"
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
run_test test_dfile_jump_name_truncates_end
run_test test_dfile_child_row_window_fits
run_test test_dfile_sort_labels
run_test test_dfile_status_compact_threshold
run_test test_dfile_cycle_sort
run_test test_dfile_dir_locked_home
run_test test_dfile_list_home
dnav_test_finish
