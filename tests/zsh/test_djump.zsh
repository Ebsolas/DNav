#!/usr/bin/env zsh
# djump + dfavorite (zsh)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh

test_load_jumps() {
  _DJUMP_LOADED=0
  assert_ok _djump_load
  assert_ge "$#_DJUMP_KEYS" 4 "loaded fixture jumps"
  assert_ok _djump_resolve home
  assert_ok _djump_resolve dhome
}

test_resolve_home() {
  local got want
  got="$(_djump_resolve home)"
  want="${HOME:A}"
  if [[ $got == "$want" || $got == "$HOME" || ${got:A} == "$want" ]]; then
    _dnav_test_pass "home resolves to HOME"
  else
    _dnav_test_fail "home resolve got=$got want=$want"
  fi
}

test_resolve_doc() {
  local got want
  got="$(_djump_resolve doc)"
  want="${HOME:A}/Documents"
  if [[ $got == "$want" || $got == "$HOME/Documents" || ${got:A} == "${HOME:A}/Documents" ]]; then
    _dnav_test_pass "doc -> Documents"
  else
    # create path may not exist as :A of missing — fixture has Documents
    assert_dir "$HOME/Documents"
    if [[ -d $got ]]; then
      _dnav_test_pass "doc resolves to existing dir $got"
    else
      _dnav_test_fail "doc resolve got=$got"
    fi
  fi
}

test_resolve_unknown() {
  assert_fail _djump_resolve nosuchkey999
}

test_match_query() {
  local hits
  hits="$(_djump_match_query home)"
  assert_contains "$hits" "home" "match home"
  hits="$(_djump_match_query dproj)"
  assert_contains "$hits" "proj" "match dproj -> proj"
  hits="$(_djump_match_query pr)"
  assert_contains "$hits" "proj" "prefix pr"
}

test_goto_changes_directory() {
  local start dest
  start="$PWD"
  DNAV_CFG_SUCCESS_ANIM=0
  _dnav_success_bar() { : }
  _djump_goto doc >/dev/null 2>&1
  dest="$PWD"
  if [[ $dest == "$HOME/Documents" || ${dest:A} == "${HOME:A}/Documents" ]]; then
    _dnav_test_pass "cd to Documents"
  else
    _dnav_test_fail "goto doc landed in $dest"
  fi
  cd -- "$start" || true
}

test_shell_cmd_installed() {
  assert_fn dhome
  assert_fn ddoc
  assert_fn dproj
}

test_dfavorite_add_list_remove() {
  local start list
  start="$PWD"
  cd -- "$HOME/Apps" || return 1
  assert_ok dfavorite add myfav
  assert_ok _djump_resolve myfav
  assert_fn dmyfav
  list="$(dfavorite list)"
  assert_contains "$list" "myfav" "listed after add"
  assert_ok dfavorite remove myfav
  assert_fail _djump_resolve myfav
  cd -- "$start" || true
}

test_dfavorite_invalid_label() {
  assert_fail dfavorite add 'bad-label'
  assert_fail dfavorite add '1leadingdigit'
}

test_store_path_tilde() {
  local got
  got="$(_djump_store_path "$HOME/Documents")"
  assert_eq "$got" "~/Documents" "store as ~ path"
}

run_test test_load_jumps
run_test test_resolve_home
run_test test_resolve_doc
run_test test_resolve_unknown
run_test test_match_query
run_test test_goto_changes_directory
run_test test_shell_cmd_installed
run_test test_dfavorite_add_list_remove
run_test test_dfavorite_invalid_label
run_test test_store_path_tilde
dnav_test_finish
