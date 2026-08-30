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

test_index_ttl_zero_fresh_not_stale() {
  local idx save="${DNAV_CFG_INDEX_TTL_HOURS:-24}"
  idx="$(_dsearch_index_path)"
  dnav_test_write_index "$idx"
  DNAV_CFG_INDEX_TTL_HOURS=0
  if _dsearch_index_stale "$idx"; then
    _dnav_test_fail "ttl 0 should not treat a present index as stale"
  else
    _dnav_test_pass "ttl 0 keeps a present index"
  fi
  rm -f -- "$DNAV_TEST_TMP/no-idx"
  if _dsearch_index_stale "$DNAV_TEST_TMP/no-idx"; then
    _dnav_test_pass "ttl 0 still treats missing as stale"
  else
    _dnav_test_fail "missing index should stay stale when ttl is 0"
  fi
  DNAV_CFG_INDEX_TTL_HOURS=$save
}

test_index_wanted_respects_auto_and_when() {
  local save_auto="${DNAV_CFG_INDEX_AUTO:-1}" save_when="${DNAV_CFG_INDEX_WHEN:-open}"
  DNAV_CFG_INDEX_AUTO=0
  DNAV_CFG_INDEX_WHEN=open
  if _dsearch_index_wanted open || _dsearch_index_wanted search; then
    _dnav_test_fail "auto 0 should want neither context"
  else
    _dnav_test_pass "auto 0 wants no auto index"
  fi
  DNAV_CFG_INDEX_AUTO=1
  DNAV_CFG_INDEX_WHEN=search
  if _dsearch_index_wanted open; then
    _dnav_test_fail "when=search should not index on open"
  else
    _dnav_test_pass "when=search skips open"
  fi
  assert_ok _dsearch_index_wanted search
  DNAV_CFG_INDEX_WHEN=open
  assert_ok _dsearch_index_wanted open
  assert_ok _dsearch_index_wanted search
  DNAV_CFG_INDEX_AUTO=$save_auto
  DNAV_CFG_INDEX_WHEN=$save_when
}

test_ensure_index_auto_off_does_not_start() {
  local idx save="${DNAV_CFG_INDEX_AUTO:-1}"
  idx="$(_dsearch_index_path)"
  rm -f -- "$idx"
  DNAV_CFG_INDEX_AUTO=0
  _DSEARCH_INDEX_STATE=idle
  _DSEARCH_INDEX_PID=0
  _dsearch_ensure_index
  if _dsearch_index_running; then
    _dsearch_index_cancel
    _dnav_test_fail "auto 0 must not start a worker"
  else
    _dnav_test_pass "auto 0 ensure_index does not start"
  fi
  DNAV_CFG_INDEX_AUTO=$save
  dnav_test_write_index "$idx"
}

test_reindex_help() {
  local got
  got="$(_dsearch_reindex --help)"
  assert_contains "$got" "Usage: dnav --reindex" "reindex help usage"
  assert_contains "$got" "--from" "reindex help lists --from"
  if [[ $got == *$'\e'* ]]; then
    _dnav_test_fail "reindex help should be plain text"
  else
    _dnav_test_pass "reindex help is pipe-friendly"
  fi
}

test_import_index_from_file() {
  local src="$DNAV_TEST_TMP/import.list" idx n
  idx="$(_dsearch_index_path)"
  print -r -- "# comment" > "$src"
  print -r -- "" >> "$src"
  print -r -- "$HOME/Documents" >> "$src"
  print -r -- "$HOME/no-such-dir" >> "$src"
  print -r -- "~/Projects" >> "$src"
  n="$(_dsearch_import_index "$src")"
  assert_eq "$n" "2" "import keeps two existing dirs"
  assert_file "$idx"
  local txt
  txt="$(<"$idx")"
  assert_contains "$txt" "$HOME/Documents" "imported Documents"
  assert_contains "$txt" "$HOME/Projects" "imported Projects"
  if [[ $txt == *no-such-dir* ]]; then
    _dnav_test_fail "import kept a missing path"
  else
    _dnav_test_pass "import dropped missing paths"
  fi
  dnav_test_write_index "$idx"
}

test_sidecar_skips_unchanged_root() {
  local idx count meta
  idx="$(_dsearch_index_path)"
  dnav_test_write_index "$idx"
  print -r -- "$HOME/.sidecar-sentinel" >> "$idx"
  meta="$(_dsearch_meta_path)"
  {
    print -r -- "v 1"
    print -r -- "r $HOME"
    _dsearch_top_children "$HOME" | while IFS= read -r line; do
      [[ -n $line ]] && print -r -- "c $line"
    done
  } > "$meta"
  count="$DNAV_TEST_TMP/idx.count"
  DNAV_INDEX_FULL=0
  _dsearch_build_index_with_count "$idx" "$count" "$DNAV_TEST_TMP/idx.building"
  local txt
  txt="$(<"$idx")"
  if [[ $txt == *sidecar-sentinel* ]]; then
    _dnav_test_pass "unchanged root kept sentinel from old index"
  else
    _dnav_test_fail "sidecar skip re-walked and dropped sentinel"
  fi
  DNAV_INDEX_FULL=1
  _dsearch_build_index_with_count "$idx" "$count" "$DNAV_TEST_TMP/idx.building"
  txt="$(<"$idx")"
  if [[ $txt == *sidecar-sentinel* ]]; then
    _dnav_test_fail "full rebuild should drop sentinel"
  else
    _dnav_test_pass "full rebuild drops sidecar sentinel"
  fi
  unset DNAV_INDEX_FULL
  dnav_test_write_index "$idx"
}

test_apply_filter_returns_matches() {
  _dsearch_apply_filter "home" 10
  assert_gt "$#_dsearch_matches" 0 "filter 'home' returns matches"
}

test_apply_filter_one_char() {
  _dsearch_apply_filter "d" 10
  assert_gt "$#_dsearch_matches" 0 "one-char 'd' returns matches"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *Documents* || $joined == *Downloads* || $joined == *docs* || $joined == *dnav* ]]; then
    _dnav_test_pass "one-char results include a d* path"
  else
    _dnav_test_fail "unexpected one-char set: $joined"
  fi
  assert_eq "${_dsearch_matches[1][1]}" "/" "match is absolute (zsh 1-based)"
}

test_apply_filter_fuzzy_doc() {
  _dsearch_apply_filter "doc" 10
  assert_gt "$#_dsearch_matches" 0 "fuzzy 'doc'"
  local joined="${(j:\n:)_dsearch_matches}"
  assert_contains "$joined" "Documents" "Documents ranked for doc"
}

test_apply_filter_proj() {
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

# 0 if $1 contains both needles (case-insensitive).
_dsearch_test_has_both() {
  emulate -L zsh
  local p="${(L)1}"
  [[ $p == *${(L)2}* && $p == *${(L)3}* ]]
}

# Fail unless $1 appears in matches, and before $2 when $2 is also present.
_dsearch_test_ranks_before() {
  emulate -L zsh
  local want="$1" other="$2" label="$3"
  local p i=0 iw=0 io=0
  for p in "${_dsearch_matches[@]}"; do
    (( i++ ))
    [[ $p == $want ]] && (( iw == 0 )) && iw=$i
    [[ $p == $other ]] && (( io == 0 )) && io=$i
  done
  (( iw > 0 )) || {
    _dnav_test_fail "$label: missing $want in ${(j:\n:)_dsearch_matches}"
    return 1
  }
  if (( io > 0 && io < iw )); then
    _dnav_test_fail "$label: $other ranked above $want"
    return 1
  fi
  _dnav_test_pass "$label"
  return 0
}

# Fail unless all-token hits (both needles) appear before any one-word near-miss.
_dsearch_test_both_before_partial() {
  emulate -L zsh
  local a="$1" b="$2"
  local p i=0 first_both=0 first_partial=0
  for p in "${_dsearch_matches[@]}"; do
    (( i++ ))
    if _dsearch_test_has_both "$p" "$a" "$b"; then
      (( first_both == 0 )) && first_both=$i
    else
      (( first_partial == 0 )) && first_partial=$i
    fi
  done
  (( first_both > 0 )) || {
    _dnav_test_fail "no both-word hit for $a+$b: ${(j:\n:)_dsearch_matches}"
    return 1
  }
  if (( first_partial > 0 && first_partial < first_both )); then
    _dnav_test_fail "near-miss ranked above both-word hit ($a $b): ${(j:\n:)_dsearch_matches}"
    return 1
  fi
  _dnav_test_pass "both-word hits outrank near-misses ($a $b)"
  return 0
}

test_apply_filter_and_tokens_any_order() {
  _dsearch_apply_filter "dnav config" 10
  assert_gt "$#_dsearch_matches" 0 "dnav config has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/dnav* || $joined == *dnav-demo/config* ]]; then
    _dnav_test_pass "hits a path that has both words"
  else
    _dnav_test_fail "missed both-word paths: $joined"
  fi
  _dsearch_test_both_before_partial dnav config
  _dsearch_apply_filter "config dnav" 10
  assert_gt "$#_dsearch_matches" 0 "order does not matter"
  joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/dnav* || $joined == *dnav-demo/config* ]]; then
    _dnav_test_pass "config dnav still hits both-word paths"
  else
    _dnav_test_fail "reversed tokens missed both-word paths: $joined"
  fi
  _dsearch_test_both_before_partial config dnav
}

test_apply_filter_and_partial_tokens() {
  _dsearch_apply_filter "dnav con" 10
  assert_gt "$#_dsearch_matches" 0 "partial con matches config"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/dnav* || $joined == *dnav-demo/config* ]]; then
    _dnav_test_pass "dnav con hits a config+dnav path"
  else
    _dnav_test_fail "dnav con missed partial config: $joined"
  fi
  _dsearch_apply_filter "dnav qzzz" 10
  if (( $#_dsearch_matches == 0 )); then
    _dnav_test_fail "dnav qzzz should keep dnav near-misses"
  else
    local p bad=0
    for p in "${_dsearch_matches[@]}"; do
      if [[ ${(L)p} != *dnav* ]]; then
        bad=1
        _dnav_test_fail "dnav qzzz near-miss without dnav: $p"
      fi
    done
    (( bad == 0 )) && _dnav_test_pass "dnav qzzz keeps dnav near-misses"
  fi
  _dsearch_apply_filter "dnav" 50
  _dsearch_apply_filter "dnav " 50
  assert_gt "$#_dsearch_matches" 0 "trailing space does not wipe hits"
  _dsearch_apply_filter "dnav c" 50
  assert_gt "$#_dsearch_matches" 0 "second word can grow from a space"
}

test_apply_filter_and_complete_strings() {
  _dsearch_apply_filter "config cmus" 10
  assert_gt "$#_dsearch_matches" 0 "config cmus hits a real cmus path"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/cmus* ]]; then
    _dnav_test_pass "config cmus hits ~/.config/cmus"
  else
    _dnav_test_fail "missed ~/.config/cmus: $joined"
  fi
  _dsearch_test_both_before_partial config cmus
  _dsearch_apply_filter "cmus" 10
  joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *chromium* ]]; then
    _dnav_test_fail "cmus letter-skipped into chromium: $joined"
  else
    _dnav_test_pass "cmus does not match chromium"
  fi
  if [[ $joined == *.config/cmus* ]]; then
    _dnav_test_pass "single-word cmus still hits ~/.config/cmus"
  else
    _dnav_test_fail "single-word cmus missed: $joined"
  fi
}

test_apply_filter_typos_plurals_related() {
  _dsearch_apply_filter "confgi" 10
  assert_gt "$#_dsearch_matches" 0 "typo confgi has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config* || $joined == */config ]]; then
    _dnav_test_pass "confgi ranks a config path"
  else
    _dnav_test_fail "confgi missed config: $joined"
  fi
  if [[ $joined == *chromium* ]]; then
    _dnav_test_fail "confgi leaked chromium: $joined"
  else
    _dnav_test_pass "confgi does not match chromium"
  fi
  _dsearch_apply_filter "configs" 10
  joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config* || $joined == */config ]]; then
    _dnav_test_pass "plural configs hits config"
  else
    _dnav_test_fail "configs missed config: $joined"
  fi
  _dsearch_apply_filter "time" 10
  joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *clock* ]]; then
    _dnav_test_fail "time should not synonym-match clock: $joined"
  else
    _dnav_test_pass "time does not special-case clock"
  fi
}

test_apply_filter_confidence_trim() {
  _dsearch_apply_filter "cmus" 10
  assert_gt "$#_dsearch_matches" 0 "cmus has hits"
  local first="${_dsearch_matches[1]}"
  if [[ $first == *.config/cmus && $first != *.config/cmus/* ]]; then
    _dnav_test_pass "exact cmus folder is first"
  else
    _dnav_test_fail "expected ~/.config/cmus first, got $first"
  fi
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *playlists* ]]; then
    _dnav_test_fail "high-confidence cmus still listed child playlists: $joined"
  else
    _dnav_test_pass "child of exact cmus is collapsed"
  fi
  if [[ $joined == *chromium* ]]; then
    _dnav_test_fail "cmus listed chromium: $joined"
  else
    _dnav_test_pass "low-confidence chromium stays out"
  fi
}

test_apply_filter_typeahead() {
  _dsearch_apply_filter "config nvi" 10
  assert_gt "$#_dsearch_matches" 0 "typeahead config nvi has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/nvim* ]]; then
    _dnav_test_pass "config nvi typeahead hits ~/.config/nvim"
  else
    _dnav_test_fail "config nvi missed nvim: $joined"
  fi
  _dsearch_test_both_before_partial config nvi
}

test_apply_filter_soft_and_rank() {
  _dsearch_apply_filter "config nvim" 10
  assert_gt "$#_dsearch_matches" 0 "config nvim has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/nvim* ]]; then
    _dnav_test_pass "config nvim hits ~/.config/nvim"
  else
    _dnav_test_fail "missed ~/.config/nvim: $joined"
  fi
  _dsearch_test_both_before_partial config nvim
  local first="${_dsearch_matches[1]}"
  if [[ $first == *.config/nvim && $first != *.config/nvim/* ]]; then
    _dnav_test_pass "exact ~/.config/nvim is first"
  else
    _dnav_test_fail "expected ~/.config/nvim first, got $first"
  fi
  if [[ $joined == *nvim-plugin* ]]; then
    local p i=0 nvim_i=0 plugin_i=0
    for p in "${_dsearch_matches[@]}"; do
      (( i++ ))
      [[ $p == *.config/nvim && $p != *.config/nvim/* ]] && (( nvim_i == 0 )) && nvim_i=$i
      [[ $p == *nvim-plugin* ]] && (( plugin_i == 0 )) && plugin_i=$i
    done
    if (( plugin_i > 0 && nvim_i > 0 && plugin_i < nvim_i )); then
      _dnav_test_fail "nvim-plugin outranked ~/.config/nvim"
    else
      _dnav_test_pass "nvim-only near-miss stays below both-word hit"
    fi
  else
    _dnav_test_pass "nvim-only near-miss not needed in top 10"
  fi
}

test_pref_home_beats_system() {
  _dsearch_apply_filter "doc" 10
  assert_gt "$#_dsearch_matches" 0 "doc has hits"
  _dsearch_test_ranks_before "$HOME/Documents" "/usr/share/doc" "Documents outranks /usr/share/doc"
}

test_pref_config_root_beats_deep() {
  _dsearch_apply_filter "config" 10
  assert_gt "$#_dsearch_matches" 0 "config has hits"
  local first="${_dsearch_matches[1]}"
  if [[ $first == "$HOME/.config" ]]; then
    _dnav_test_pass "~/.config is first for config"
  else
    _dnav_test_fail "expected ~/.config first, got $first"
  fi
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *Default/Extensions* ]]; then
    _dnav_test_fail "deep chromium still listed for config: $joined"
  else
    _dnav_test_pass "deep chromium not listed for config"
  fi
}

test_pref_share_root_beats_deeper() {
  _dsearch_apply_filter "share" 10
  assert_gt "$#_dsearch_matches" 0 "share has hits"
  _dsearch_test_ranks_before "$HOME/.local/share" "$HOME/.local/share/app/share" \
    "~/.local/share outranks deeper share"
}

test_pref_leaf_intent_allows_deep() {
  _dsearch_apply_filter "playlists" 10
  assert_gt "$#_dsearch_matches" 0 "playlists has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  if [[ $joined == *.config/cmus/playlists* ]]; then
    _dnav_test_pass "leaf intent still finds cmus/playlists"
  else
    _dnav_test_fail "playlists missed cmus/playlists: $joined"
  fi
}

test_pref_cache_demoted() {
  _dsearch_apply_filter "dnav" 10
  assert_gt "$#_dsearch_matches" 0 "dnav has hits"
  _dsearch_test_ranks_before "$HOME/.config/dnav" "$HOME/.cache/dnav" \
    "~/.config/dnav outranks cache dnav"
  _dsearch_test_ranks_before "$HOME/.local/share/dnav" "$HOME/.cache/dnav" \
    "~/.local/share/dnav outranks cache dnav"
}

test_apply_filter_empty_query() {
  _dsearch_matches=(/tmp/leftover)
  _dsearch_apply_filter "" 10
  assert_eq "$#_dsearch_matches" "0" "empty query clears matches"
}

test_typing_still_hits() {
  _dsearch_apply_filter "d" 50
  local n1=$#_dsearch_matches
  _dsearch_apply_filter "do" 50
  local n2=$#_dsearch_matches
  _dsearch_apply_filter "doc" 50
  local n3=$#_dsearch_matches
  assert_gt "$n1" 0 "d has hits"
  assert_gt "$n2" 0 "do has hits"
  assert_gt "$n3" 0 "doc has hits"
  local joined="${(j:\n:)_dsearch_matches}"
  assert_contains "$joined" "Documents" "doc still ranks Documents"
}

test_awk_filter_direct() {
  local idx
  local -a out
  idx="$(_dsearch_index_path)"
  out=("${(@f)$(_dsearch_awk_filter "home" 5 "$idx")}")
  assert_gt "$#out" 0 "awk filter stdout"
}

test_display_path_tilde() {
  local got
  got="$(_dsearch_display_path "$HOME/Documents")"
  assert_eq "$got" "~/Documents"
}

test_pin_jumps_prefers_jump() {
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

test_collect_roots_default_is_home() {
  local oldhome="$HOME"
  local -a roots
  unset DNAV_SEARCH_ROOTS DNAV_SEARCH_LIGHT
  HOME="$DNAV_TEST_HOME"
  roots=("${(@f)$(_dsearch_collect_roots)}")
  HOME="$oldhome"
  if (( $#roots == 1 )) && [[ ${roots[1]:a} == "${DNAV_TEST_HOME:a}" ]]; then
    _dnav_test_pass "default root is HOME only"
  else
    _dnav_test_fail "default roots($#roots)=${roots[*]}"
  fi
}

test_collect_roots_env_override() {
  local extra="$DNAV_TEST_TMP/extra-root"
  local -a roots
  mkdir -p -- "$extra"
  DNAV_SEARCH_ROOTS="$HOME $extra"
  roots=("${(@f)$(_dsearch_collect_roots)}")
  unset DNAV_SEARCH_ROOTS
  if (( $#roots == 2 )); then
    _dnav_test_pass "SEARCH_ROOTS adds a second root"
  else
    _dnav_test_fail "override roots($#roots)=${roots[*]}"
  fi
}

test_index_cancel_refuses_pid_1() {
  _DSEARCH_INDEX_PID=1
  _DSEARCH_INDEX_HAS_SID=1
  _dsearch_index_cancel
  assert_eq "$_DSEARCH_INDEX_PID" "0" "pid 1 not kept"
}

test_index_module_standalone() {
  local out
  out="$(zsh -fc '
    emulate -L zsh
    source "'"$ROOT"'/zsh/dsearch-index"
    (( $+functions[_dsearch_reindex] )) || exit 1
    (( $+functions[_dsearch_start] )) && exit 2
    _dsearch_reindex --help
  ')" || {
    _dnav_test_fail "dsearch-index alone failed (exit $?)"
    return
  }
  assert_contains "$out" "Usage: dnav --reindex" "index file has reindex help"
  if (( $+functions[_dsearch_start] )); then
    _dnav_test_pass "parent still has search UI from setup"
  fi
}

test_search_plugin_loads_index() {
  assert_fn _dsearch_reindex
  assert_fn _dsearch_start
  assert_fn _dsearch_apply_filter
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
run_test test_collect_roots_default_is_home
run_test test_collect_roots_env_override
run_test test_index_cancel_refuses_pid_1
run_test test_index_module_standalone
run_test test_search_plugin_loads_index
run_test test_index_path
run_test test_index_not_stale_when_fresh
run_test test_index_stale_when_missing
run_test test_index_ttl_zero_fresh_not_stale
run_test test_index_wanted_respects_auto_and_when
run_test test_ensure_index_auto_off_does_not_start
run_test test_reindex_help
run_test test_import_index_from_file
run_test test_sidecar_skips_unchanged_root
run_test test_apply_filter_returns_matches
run_test test_apply_filter_one_char
run_test test_apply_filter_fuzzy_doc
run_test test_apply_filter_proj
run_test test_apply_filter_and_tokens_any_order
run_test test_apply_filter_and_partial_tokens
run_test test_apply_filter_and_complete_strings
run_test test_apply_filter_typos_plurals_related
run_test test_apply_filter_confidence_trim
run_test test_apply_filter_typeahead
run_test test_apply_filter_soft_and_rank
run_test test_pref_home_beats_system
run_test test_pref_config_root_beats_deep
run_test test_pref_share_root_beats_deeper
run_test test_pref_leaf_intent_allows_deep
run_test test_pref_cache_demoted
run_test test_query_caret_edit
run_test test_apply_filter_empty_query
test_preview_narrows_prefix() {
  _dsearch_q="doc"
  _DSEARCH_SHOWN_Q="do"
  _dsearch_matches=("$HOME/Documents" "$HOME/Downloads" "$HOME/Projects")
  if _dsearch_preview_if_prefix; then
    local joined="${(j:\n:)_dsearch_matches}"
    assert_contains "$joined" "Documents" "prefix preview keeps Documents"
  else
    _dnav_test_fail "prefix preview should run for doc after do"
  fi
}

test_wait_key_idle_ticks() {
  _DSEARCH_PUSHBACK=""
  DNAV_ABORT=0
  if _dsearch_wait_key </dev/null; then
    _dnav_test_fail "idle wait_key should tick (no key)"
  else
    _dnav_test_pass "idle wait_key is a tick"
  fi
}

test_now_ms_is_integer() {
  local n
  n="$(_dsearch_now_ms)"
  if [[ $n == <-> ]]; then
    _dnav_test_pass "now_ms is an integer ($n)"
  else
    _dnav_test_fail "now_ms not integer: ${(V)n}"
  fi
}

test_worker_ranks_off_thread() {
  _dsearch_q="doc"
  _dsearch_matches=()
  _DSEARCH_WORKER_PID=0
  _DSEARCH_GEN=0
  _DSEARCH_SHOWN_Q=""
  _DSEARCH_WORK_Q=""
  _DSEARCH_LAST_TICK=0
  _dsearch_worker_start
  assert_gt "$_DSEARCH_WORKER_PID" 1 "worker pid is a real child"
  local i
  for (( i=0; i < 80; i++ )); do
    _dsearch_worker_poll && break
    if zmodload -F zsh/zselect b:zselect 2>/dev/null; then
      zselect -t 5
    else
      /bin/sleep 0.05
    fi
  done
  _dsearch_worker_stop
  assert_gt "$#_dsearch_matches" 0 "background worker ranks doc"
  local joined="${(j:\n:)_dsearch_matches}"
  assert_contains "$joined" "Documents" "async hits include Documents"
  assert_eq "$_DSEARCH_SHOWN_Q" "doc" "poll records the query that was ranked"
}

test_worker_reap_on_poll() {
  _dsearch_q="doc"
  _dsearch_matches=()
  _DSEARCH_WORKER_PID=0
  _DSEARCH_GEN=0
  _DSEARCH_SHOWN_Q=""
  _DSEARCH_WORK_Q=""
  _DSEARCH_LAST_TICK=0
  _dsearch_worker_start
  local pid=$_DSEARCH_WORKER_PID i stat
  for (( i=0; i < 80; i++ )); do
    _dsearch_worker_poll && break
    if zmodload -F zsh/zselect b:zselect 2>/dev/null; then
      zselect -t 5
    else
      /bin/sleep 0.05
    fi
  done
  _dsearch_worker_stop
  assert_eq "$_DSEARCH_WORKER_PID" "0" "poll/stop cleared worker pid"
  stat="$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  if [[ $stat == *Z* ]]; then
    _dnav_test_fail "worker left as zombie (pid $pid)"
  else
    _dnav_test_pass "worker reaped (state=${stat:-gone})"
  fi
}

test_commit_target_uses_visible_sel() {
  functions -c _dsearch_flush_filter _dsearch_flush_filter_orig
  _dsearch_matches=("$HOME/Documents" "$HOME/Downloads")
  _dsearch_sel=1
  _dsearch_q="doc"
  _DSEARCH_SHOWN_Q="do"
  _dsearch_flush_filter() {
    _dnav_test_fail "Enter should not flush when a row is already selected"
  }
  _dsearch_commit_target
  unfunction _dsearch_flush_filter
  functions -c _dsearch_flush_filter_orig _dsearch_flush_filter
  unfunction _dsearch_flush_filter_orig
  assert_eq "$REPLY" "$HOME/Downloads" "Enter keeps the highlighted row"
  assert_eq "$_dsearch_sel" "1" "selection stays on that row"
}

test_commit_target_flushes_when_empty() {
  functions -c _dsearch_flush_filter _dsearch_flush_filter_orig
  _dsearch_matches=()
  _dsearch_sel=0
  _dsearch_flush_filter() {
    _dsearch_matches=("$HOME/Documents")
  }
  _dsearch_commit_target
  unfunction _dsearch_flush_filter
  functions -c _dsearch_flush_filter_orig _dsearch_flush_filter
  unfunction _dsearch_flush_filter_orig
  assert_eq "$REPLY" "$HOME/Documents" "empty list flushes then takes the top hit"
}

test_commit_target_clamps_sel() {
  functions -c _dsearch_flush_filter _dsearch_flush_filter_orig
  _dsearch_matches=("$HOME/Documents" "$HOME/Downloads")
  _dsearch_sel=9
  _dsearch_flush_filter() {
    _dnav_test_fail "clamp should not re-rank"
  }
  _dsearch_commit_target
  unfunction _dsearch_flush_filter
  functions -c _dsearch_flush_filter_orig _dsearch_flush_filter
  unfunction _dsearch_flush_filter_orig
  assert_eq "$REPLY" "$HOME/Downloads" "out-of-range sel clamps to last row"
  assert_eq "$_dsearch_sel" "1" "sel clamped"
}

run_test test_typing_still_hits
run_test test_preview_narrows_prefix
run_test test_wait_key_idle_ticks
run_test test_now_ms_is_integer
run_test test_worker_ranks_off_thread
run_test test_worker_reap_on_poll
run_test test_commit_target_uses_visible_sel
run_test test_commit_target_flushes_when_empty
run_test test_commit_target_clamps_sel
run_test test_awk_filter_direct
run_test test_display_path_tilde
run_test test_pin_jumps_prefers_jump
run_test test_find_dirs_exists_dead_hooks_gone
dnav_test_finish
