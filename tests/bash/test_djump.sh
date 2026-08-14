#!/usr/bin/env bash
# djump + dfavorite
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/bash_env.sh
source "$ROOT/tests/lib/bash_env.sh"

dnav_test_setup_bash

test_load_jumps() {
  _DJUMP_LOADED=0
  assert_ok _djump_load
  assert_ge "${#_DJUMP_KEYS[@]}" 4 "loaded fixture jumps"
  assert_ok _djump_resolve home
  assert_ok _djump_resolve dhome
}

test_resolve_home() {
  local got
  got="$(_djump_resolve home)"
  got="${got%$'\n'}"
  # realpath may resolve; compare via abspath of HOME
  local want
  want="$(_djump_abspath "$HOME")"
  want="${want%$'\n'}"
  assert_eq "$got" "$want" "home resolves to HOME"
}

test_resolve_doc() {
  local got want
  got="$(_djump_resolve doc)"; got="${got%$'\n'}"
  want="$(_djump_abspath "$HOME/Documents")"; want="${want%$'\n'}"
  assert_eq "$got" "$want" "doc -> Documents"
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
  # Suppress success bar paint noise in test output
  DNAV_CFG_SUCCESS_ANIM=0
  _dnav_success_bar() { :; }
  _djump_goto doc >/dev/null 2>&1
  dest="$PWD"
  assert_eq "$dest" "$(_djump_abspath "$HOME/Documents")" "cd to Documents"
  cd -- "$start" || true
}

test_shell_cmd_installed() {
  assert_ok declare -f dhome
  assert_ok declare -f ddoc
  assert_ok declare -f dproj
}

test_dfavorite_add_list_remove() {
  local start
  start="$PWD"
  cd -- "$HOME/Apps" || return 1
  assert_ok dfavorite add myfav
  assert_ok _djump_resolve myfav
  assert_ok declare -f dmyfav
  local list
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
  got="${got%$'\n'}"
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
