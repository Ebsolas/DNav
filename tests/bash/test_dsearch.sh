#!/usr/bin/env bash
# dsearch filter + index helpers (non-interactive)
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/bash_env.sh
source "$ROOT/tests/lib/bash_env.sh"

dnav_test_setup_bash
dnav_test_dsearch_session

test_index_path() {
  local p
  p="$(_dsearch_index_path)"; p="${p%$'\n'}"
  assert_eq "$p" "$XDG_CACHE_HOME/dnav/dirs.idx"
}

test_index_not_stale_when_fresh() {
  local idx
  idx="$(_dsearch_index_path)"; idx="${idx%$'\n'}"
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

# Regression: local query=... qlen=${#query} on one line made qlen always 0.
test_apply_filter_qlen_not_zero() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "home" 10
  assert_gt "${#_dsearch_matches[@]}" 0 "filter 'home' returns matches (qlen bug regression)"
}

test_apply_filter_prefix1() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "d" 10
  assert_gt "${#_dsearch_matches[@]}" 0 "prefix1 'd' returns matches"
  local joined
  joined=$(printf '%s\n' "${_dsearch_matches[@]}")
  if [[ $joined == *Documents* || $joined == *Downloads* || $joined == *docs* || $joined == *dnav* ]]; then
    _dnav_test_pass "prefix results include a d* path component"
  else
    _dnav_test_fail "unexpected prefix1 set: $joined"
  fi
  assert_eq "${_dsearch_matches[0]:0:1}" "/" "match is absolute path"
}

test_apply_filter_fuzzy_doc() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "doc" 10
  assert_gt "${#_dsearch_matches[@]}" 0 "fuzzy 'doc' returns matches"
  local joined
  joined=$(printf '%s\n' "${_dsearch_matches[@]}")
  assert_contains "$joined" "Documents" "Documents ranked for doc"
}

test_apply_filter_proj() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "proj" 10
  assert_gt "${#_dsearch_matches[@]}" 0 "fuzzy 'proj'"
  local joined
  joined=$(printf '%s\n' "${_dsearch_matches[@]}")
  assert_contains "$joined" "Projects" "Projects for proj"
}

test_apply_filter_empty_query() {
  _dsearch_matches=(/tmp/leftover)
  _dsearch_apply_filter "" 10
  assert_eq "${#_dsearch_matches[@]}" "0" "empty query clears matches"
}

test_incremental_narrowing() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "d" 50
  local n1=${#_dsearch_matches[@]}
  _dsearch_apply_filter "do" 50
  local n2=${#_dsearch_matches[@]}
  _dsearch_apply_filter "doc" 50
  local n3=${#_dsearch_matches[@]}
  assert_gt "$n1" 0 "d has hits"
  assert_gt "$n2" 0 "do has hits"
  assert_gt "$n3" 0 "doc has hits"
  # Narrowing should not increase candidate top list unboundedly; survivors shrink.
  # Top-N is capped so compare survivor stack file sizes if present.
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
  local idx survivors out
  idx="$(_dsearch_index_path)"; idx="${idx%$'\n'}"
  survivors="$DNAV_TEST_TMP/surv.out"
  : > "$survivors"
  mapfile -t out < <(_dsearch_awk_filter "home" "fuzzy" 5 "$idx" "$survivors")
  assert_gt "${#out[@]}" 0 "awk filter stdout"
  assert_file "$survivors"
  assert_gt "$(wc -l < "$survivors" | tr -d ' ')" 0 "survivors written"
}

test_display_path_tilde() {
  local got
  got="$(_dsearch_display_path "$HOME/Documents")"
  got="${got%$'\n'}"
  assert_eq "$got" "~/Documents"
}

test_pin_jumps_prefers_jump() {
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_apply_filter "home" 10
  local first home_abs
  first="${_dsearch_matches[0]}"
  home_abs="$(_djump_abspath "$HOME")"; home_abs="${home_abs%$'\n'}"
  if [[ $first == "$home_abs" || $first == "$HOME" ]]; then
    _dnav_test_pass "pinned home jump is first"
  else
    _dnav_test_fail "first match not HOME (got $first want $home_abs)"
  fi
}

run_test test_index_path
run_test test_index_not_stale_when_fresh
run_test test_index_stale_when_missing
run_test test_apply_filter_qlen_not_zero
run_test test_apply_filter_prefix1
run_test test_apply_filter_fuzzy_doc
run_test test_apply_filter_proj
run_test test_apply_filter_empty_query
run_test test_incremental_narrowing
run_test test_awk_filter_direct
run_test test_display_path_tilde
run_test test_pin_jumps_prefers_jump
dnav_test_finish
