#!/usr/bin/env zsh
# dsearch filter + index helpers (zsh, non-interactive)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh
dnav_test_dsearch_session

test_index_path() {
  local p
  p="$(_dsearch_index_path)"
  assert_eq "$p" "$XDG_CACHE_HOME/dnav/dirs.idx"
}

test_index_not_stale_when_fresh() {
  local idx
  idx="$(_dsearch_index_path)"
  dnav_test_write_index "$idx"
  touch -- "$idx"
  if _dsearch_index_stale "$idx"; then
    _dnav_test_fail "fresh index should not be stale"
  else
    _dnav_test_pass "fresh index not stale"
  fi
}

test_index_stale_when_missing() {
  local missing="$DNAV_TEST_TMP/no-such-dirs.idx"
  rm -f -- "$missing"
  if _dsearch_index_stale "$missing"; then
    _dnav_test_pass "missing index is stale"
  else
    _dnav_test_fail "missing index should be stale"
  fi
}

test_apply_filter_returns_matches() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "home" 10
  assert_gt "$#_dsearch_matches" 0 "filter 'home' returns matches"
}

test_apply_filter_prefix1() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "d" 10
  assert_gt "$#_dsearch_matches" 0 "prefix1 'd' returns matches"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *Documents* || $joined == *Downloads* || $joined == *docs* || $joined == *dnav* ]]; then
    _dnav_test_pass "prefix results include a d* path"
  else
    _dnav_test_fail "unexpected prefix1 set: $joined"
  fi
  assert_eq "${_dsearch_matches[1][1]}" "/" "match is absolute (zsh 1-based)"
}

test_apply_filter_fuzzy_doc() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "doc" 10
  assert_gt "$#_dsearch_matches" 0 "fuzzy 'doc'"
  local joined="${(j:\n:)_dsearch_matches}"
  assert_contains "$joined" "Documents" "Documents ranked for doc"
}

test_apply_filter_proj() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "proj" 10
  assert_gt "$#_dsearch_matches" 0 "fuzzy 'proj'"
  local joined="${(j:\n:)_dsearch_matches}"
  assert_contains "$joined" "Projects" "Projects for proj"
}

test_query_caret_edit() {
  _dsearch_q=""
  _dsearch_cur=0
  _dsearch_insert p
  _dsearch_insert r
  _dsearch_insert j
  assert_eq "$_dsearch_q" "prj" "typed prj"
  assert_eq "$_dsearch_cur" "3" "caret at end"
  _dsearch_cur=2
  _dsearch_insert o
  assert_eq "$_dsearch_q" "proj" "insert o between r and j"
  assert_eq "$_dsearch_cur" "3" "caret after insert"
  _dsearch_backspace
  assert_eq "$_dsearch_q" "prj" "backspace at caret"
  assert_eq "$_dsearch_cur" "2"
  _dsearch_cur=1
  _dsearch_delete
  assert_eq "$_dsearch_q" "pj" "forward delete"
  assert_eq "$_dsearch_cur" "1"
}

test_apply_filter_empty_query() {
  _dsearch_matches=(/tmp/leftover)
  _dsearch_apply_filter "" 10
  assert_eq "$#_dsearch_matches" "0" "empty query clears matches"
}

test_incremental_narrowing() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "d" 50
  local n1=$#_dsearch_matches
  _dsearch_apply_filter "do" 50
  local n2=$#_dsearch_matches
  _dsearch_apply_filter "doc" 50
  local n3=$#_dsearch_matches
  assert_gt "$n1" 0 "d has hits"
  assert_gt "$n2" 0 "do has hits"
  assert_gt "$n3" 0 "doc has hits"
  if [[ -n ${_dsearch_cand_stack[1]:-} && -n ${_dsearch_cand_stack[3]:-} ]]; then
    local c1 c3
    c1=$(wc -l < "${_dsearch_cand_stack[1]}")
    c3=$(wc -l < "${_dsearch_cand_stack[3]}")
    c1=${c1// /}; c3=${c3// /}
    assert_ge "$c1" "$c3" "survivors shrink or stay as query lengthens"
  else
    _dnav_test_pass "cand stack present (skipped size compare)"
  fi
}

test_awk_filter_direct() {
  local idx survivors
  local -a out
  idx="$(_dsearch_index_path)"
  survivors="$DNAV_TEST_TMP/surv.out"
  : > "$survivors"
  out=("${(@f)$(_dsearch_awk_filter "home" "fuzzy" 5 "$idx" "$survivors")}")
  assert_gt "$#out" 0 "awk filter stdout"
  assert_file "$survivors"
  assert_gt "$(wc -l < "$survivors" | tr -d ' ')" 0 "survivors written"
}

test_display_path_tilde() {
  local got
  got="$(_dsearch_display_path "$HOME/Documents")"
  assert_eq "$got" "~/Documents"
}

test_pin_jumps_prefers_jump() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_apply_filter "home" 10
  local first="${_dsearch_matches[1]}"
  if [[ $first == "$HOME" || ${first:A} == "${HOME:A}" ]]; then
    _dnav_test_pass "pinned home jump is first"
  else
    _dnav_test_fail "first match not HOME (got $first)"
  fi
}

test_constrained_env_busybox_on_path() {
  local bindir="$DNAV_TEST_TMP/fakebin" path_save="$PATH"
  mkdir -p -- "$bindir"
  print -r -- $'#!/bin/sh\nexit 0\n' > "$bindir/busybox"
  chmod +x -- "$bindir/busybox"
  PATH="$bindir:$PATH"
  unset DNAV_SEARCH_LIGHT
  if _dsearch_constrained_env; then
    _dnav_test_fail "busybox on PATH must not force light mode"
  else
    _dnav_test_pass "busybox on PATH is not light mode"
  fi
  PATH="$path_save"
}

test_constrained_env_light_flag() {
  DNAV_SEARCH_LIGHT=1
  assert_ok _dsearch_constrained_env
  unset DNAV_SEARCH_LIGHT
}

test_collect_roots_space_in_home() {
  local oldhome="$HOME" dir roots_out
  local -a roots
  dir="$DNAV_TEST_TMP/My Docs"
  mkdir -p -- "$dir"
  HOME="$dir"
  DNAV_SEARCH_LIGHT=1
  unset DNAV_SEARCH_ROOTS
  roots=("${(@f)$(_dsearch_collect_roots)}")
  HOME="$oldhome"
  unset DNAV_SEARCH_LIGHT
  if (( $#roots == 1 )) && [[ ${roots[1]:A} == "${dir:A}" ]]; then
    _dnav_test_pass "space in path is one root"
  else
    _dnav_test_fail "roots($#roots)=${roots[*]}"
  fi
}

test_index_cancel_refuses_pid_1() {
  _DSEARCH_INDEX_PID=1
  _DSEARCH_INDEX_HAS_SID=1
  _dsearch_index_cancel
  assert_eq "$_DSEARCH_INDEX_PID" "0" "pid 1 not kept"
}

test_find_dirs_exists_dead_hooks_gone() {
  assert_fn _dsearch_find_dirs
  if (( $+functions[_dsearch_in_dfile] )); then
    _dnav_test_fail "_dsearch_in_dfile should be gone"
  else
    _dnav_test_pass "no _dsearch_in_dfile stub"
  fi
  if (( $+functions[_dsearch_find_prune] )); then
    _dnav_test_fail "_dsearch_find_prune should be gone (use _dsearch_find_dirs)"
  else
    _dnav_test_pass "no unused prune printer"
  fi
}

run_test test_constrained_env_busybox_on_path
run_test test_constrained_env_light_flag
run_test test_collect_roots_space_in_home
run_test test_index_cancel_refuses_pid_1
run_test test_index_path
run_test test_index_not_stale_when_fresh
run_test test_index_stale_when_missing
run_test test_apply_filter_returns_matches
run_test test_apply_filter_prefix1
run_test test_apply_filter_fuzzy_doc
run_test test_apply_filter_proj
run_test test_query_caret_edit
run_test test_apply_filter_empty_query
run_test test_incremental_narrowing
run_test test_awk_filter_direct
run_test test_display_path_tilde
run_test test_pin_jumps_prefers_jump
run_test test_find_dirs_exists_dead_hooks_gone
dnav_test_finish
