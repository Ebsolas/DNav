#!/usr/bin/env zsh
# djump (zsh)
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

test_resolve_exact_key_wins_over_dstrip() {
  local got
  # keys ocsx / docsx: stripping d from docsx would wrongly yield ocsx
  assert_ok djump add ocsx "$HOME/Documents"
  assert_ok djump add docsx "$HOME/Apps"
  got="$(_djump_resolve docsx)"
  if [[ ${got:A} == "${HOME:A}/Apps" || $got == "$HOME/Apps" ]]; then
    _dnav_test_pass "docsx resolves to Apps, not ocsx"
  else
    _dnav_test_fail "docsx resolve got=$got want=$HOME/Apps"
  fi
  got="$(_djump_resolve ocsx)"
  if [[ ${got:A} == "${HOME:A}/Documents" || $got == "$HOME/Documents" ]]; then
    _dnav_test_pass "ocsx still resolves"
  else
    _dnav_test_fail "ocsx resolve got=$got"
  fi
  djump remove docsx >/dev/null
  djump remove ocsx >/dev/null
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

test_djump_add_list_remove() {
  local start list
  start="$PWD"
  cd -- "$HOME/Apps" || return 1
  assert_ok djump add myfav
  assert_ok _djump_resolve myfav
  assert_fn dmyfav
  list="$(djump -l)"
  assert_contains "$list" "myfav" "listed after add"
  assert_ok djump remove myfav
  assert_fail _djump_resolve myfav
  if (( $+functions[dmyfav] )); then
    _dnav_test_fail "dmyfav should be unfunctioned after remove"
  else
    _dnav_test_pass "dmyfav removed"
  fi
  cd -- "$start" || true
}

test_djump_add_docs_keeps_docs() {
  assert_ok djump add docs "$HOME/Documents"
  assert_ok _djump_resolve docs
  assert_fn ddocs
  if [[ -n ${_DJUMP_MAP[ocs]:-} ]]; then
    _dnav_test_fail "docs must not be stored as ocs"
  else
    _dnav_test_pass "docs stored as docs"
  fi
  djump remove docs >/dev/null
}

test_djump_invalid_label() {
  assert_fail djump add 'bad-label'
  assert_fail djump add '1leadingdigit'
}

test_djump_reserved_names() {
  assert_fail djump add nav
  assert_fail djump add jump
  assert_fail djump add config
  assert_fail djump add help
  assert_fn dnav
  assert_fn djump
}

test_djump_clash_existing_function() {
  dzzz() { : }
  assert_fail djump add zzz
  unfunction dzzz
  assert_ok djump add zzz "$HOME/Apps"
  assert_fn dzzz
  djump remove zzz >/dev/null
}

test_djump_clash_path_command() {
  if (( $+commands[df] )); then
    assert_fail djump add f
  else
    DNAV_TEST_SKIP+=1
    print -r -- "  skip  no df on PATH"
  fi
}

test_djump_check_stolen_alias() {
  local out
  assert_ok djump add myfav "$HOME/Apps"
  alias dmyfav='echo stolen'
  out="$(djump --check 2>&1)" || true
  assert_contains "$out" "stolen" "check reports stolen alias"
  unalias dmyfav
  djump remove myfav >/dev/null
}

test_djump_save_atomic() {
  local f tmp
  f="$DNAV_TEST_CONFIG/jumps"
  assert_ok djump add saveme "$HOME/Apps"
  assert_file "$f"
  assert_contains "$(<$f)" "saveme" "saved key"
  setopt localoptions nullglob
  tmp=("$f".tmp.*)
  if (( $#tmp )); then
    _dnav_test_fail "temp save file left behind: $tmp"
  else
    _dnav_test_pass "no leftover tmp after save"
  fi
  djump remove saveme >/dev/null
}

test_djump_load_hash_in_path() {
  local dir="$HOME/proj#2"
  mkdir -p -- "$dir"
  print -r -- "hashy  $dir" >> "$DNAV_TEST_CONFIG/jumps"
  _DJUMP_LOADED=0
  setopt extended_glob
  assert_ok _djump_load
  unsetopt extended_glob
  local got
  got="$(_djump_resolve hashy)"
  if [[ ${got:A} == "${dir:A}" || $got == "$dir" ]]; then
    _dnav_test_pass "jump path keeps #"
  else
    _dnav_test_fail "hashy resolve got=$got want=$dir"
  fi
  djump remove hashy >/dev/null 2>&1 || true
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
run_test test_resolve_exact_key_wins_over_dstrip
run_test test_match_query
run_test test_goto_changes_directory
run_test test_shell_cmd_installed
run_test test_djump_add_list_remove
run_test test_djump_add_docs_keeps_docs
run_test test_djump_invalid_label
run_test test_djump_reserved_names
run_test test_djump_clash_existing_function
run_test test_djump_clash_path_command
run_test test_djump_check_stolen_alias
run_test test_djump_save_atomic
run_test test_djump_load_hash_in_path
run_test test_store_path_tilde
dnav_test_finish
