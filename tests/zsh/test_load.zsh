#!/usr/bin/env zsh
# Module load + public command surface (zsh)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh

test_djump_lazy_until_available() {
  if (( $+functions[_djump_goto] )); then
    _dnav_test_fail "sourcing dnav should not load djump"
  else
    _dnav_test_pass "djump is not sourced with dnav"
  fi
  assert_ok _djump_available
  assert_fn _djump_goto
}

test_crawler_not_sourced_with_dnav() {
  if (( $+functions[_dsearch_find_dirs] )); then
    _dnav_test_fail "dnav source should not load the crawler"
  else
    _dnav_test_pass "crawler is not sourced with dnav"
  fi
  if (( $+functions[_dindexer_available] )); then
    _dnav_test_fail "dindexer should stay lazy"
  else
    _dnav_test_pass "dindexer is not sourced with dnav"
  fi
}

test_about_lazy_until_ensure() {
  if (( $+functions[_dnav_show_about] )); then
    _dnav_test_fail "sourcing dnav should not load About"
  else
    _dnav_test_pass "About is not sourced with dnav"
  fi
  assert_ok _dnav_ensure_about
  assert_fn _dnav_show_about
  assert_fn _dnav_draw_about
}

test_update_lazy_until_load() {
  if (( $+functions[_dnav_update] )); then
    _dnav_test_fail "sourcing dnav should not load --update"
  else
    _dnav_test_pass "--update is not sourced with dnav"
  fi
  _dnav_load_module dnav-update
  assert_fn _dnav_update
  assert_fn _dnav_update_repo
}

test_zsh_stub_does_not_source_djump() {
  local out
  out="$(
    DNAV_DIR="$DNAV_ZSH_DIR" DNAV_CONFIG_DIR="$DNAV_TEST_CONFIG" HOME="$HOME" zsh -f -c '
      emulate -L zsh
      source "$1/shell/dnav.zsh"
      (( $+functions[_djump_goto] )) && exit 1
      (( $+functions[dnav] )) || exit 2
      (( $+functions[djump] )) || exit 3
      print -r -- ok
    ' zsh "$DNAV_REPO_ROOT"
  )" || {
    _dnav_test_fail "stub source failed"
    return
  }
  assert_eq "$out" "ok" "stub does not source djump"
}

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
  assert_fn _dnav_sleep_ms
  assert_fn _dnav_out
  assert_fn _dnav_success_bar
  assert_fn _dnav_usable_cols
  assert_fn _dnav_usable_from
  assert_fn _dnav_autowrap_off
  assert_fn _dnav_autowrap_on
  assert_fn _dnav_resize_chip_label
  assert_fn _dnav_tui_below
  assert_fn _dnav_logical_path
  assert_fn _dnav_status_set
  assert_fn _dnav_status_clear
  assert_fn _dnav_resolve_dir
  assert_fn _dnav_disp_w
  assert_fn _dnav_fit_start
  assert_fn _dnav_fit_end
  assert_fn _dnav_cleanup
  assert_fn _dnav_abort
  assert_fn _dnav_draw
  assert_fn _dnav_ensure_about
  _dnav_ensure_about
  assert_fn _dnav_draw_about
  assert_fn _dnav_session_reset
  assert_fn _dnav_aborted
  assert_fn _dfile_draw
  assert_fn _dfile_erase
  assert_fn _dfile_refresh
  assert_fn _dfile_session_reset
  _dnav_sync_term_size
  _dnav_test_pass "sync_term_size callable"
}

test_resize_waits_for_steady_stty() {
  assert_ge "$_DNAV_STEADY_NEED" 4 "several identical stty samples before restore"
  # maybe_resize must poll stty every idle tick; WINCH alone is not enough.
  assert_fn _dnav_maybe_resize
  assert_fn _dnav_sync_term_size
}

test_resize_chip_label_main() {
  _DSEARCH_OPEN=0
  _DFILE_OPEN=0
  _DNAV_MODE=main
  DNAV_CFG_BRAND=DNav
  assert_eq "$(_dnav_resize_chip_label)" " DNav " "main chip"
  assert_eq "$(_dnav_tui_below)" "0" "main has no extra rows"
}

test_resize_chip_label_about() {
  _DSEARCH_OPEN=0
  _DFILE_OPEN=0
  _DNAV_MODE=about
  _DNAV_HELP_EXTRA=5
  assert_eq "$(_dnav_resize_chip_label)" " DNav About:" "about chip"
  assert_eq "$(_dnav_tui_below)" "5" "about extra rows"
  _DNAV_MODE=main
  _DNAV_HELP_EXTRA=0
}

test_abort_flag_helper() {
  DNAV_ABORT=0
  if _dnav_aborted; then
    _dnav_test_fail "aborted is false when DNAV_ABORT=0"
  else
    _dnav_test_pass "aborted is false when DNAV_ABORT=0"
  fi
  DNAV_ABORT=1
  if _dnav_aborted; then
    _dnav_test_pass "aborted is true when DNAV_ABORT=1"
  else
    _dnav_test_fail "aborted is true when DNAV_ABORT=1"
  fi
  DNAV_ABORT=0
}

test_tui_below_dfile_browse_wipes_three() {
  _DSEARCH_OPEN=0
  _DFILE_OPEN=1
  _DFILE_MODE=browse
  _DFILE_BODY=0
  assert_eq "$(_dnav_tui_below)" "3" "browse wipes 3 even when BODY is still 0"
  _DFILE_BODY=3
  assert_eq "$(_dnav_tui_below)" "3" "browse stays 3 after draw"
  _DFILE_MODE=jump
  _DFILE_BODY=2
  assert_eq "$(_dnav_tui_below)" "2" "jump uses recorded extra rows"
  _DFILE_OPEN=0
  _DFILE_MODE=browse
  _DFILE_BODY=0
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

test_term_cols_reads_columns_cache() {
  local save="${COLUMNS:-}"
  COLUMNS=64
  assert_eq "$(_dnav_term_cols)" "64" "term_cols uses COLUMNS"
  assert_eq "$(_dnav_usable_cols)" "62" "usable_cols from cache (spare 2)"
  COLUMNS=100
  assert_eq "$(_dnav_term_cols)" "100" "cache update is visible"
  if [[ -n $save ]]; then
    COLUMNS=$save
  else
    unset COLUMNS
  fi
}

test_logical_path_no_symlink_resolve() {
  assert_eq "$(_dnav_logical_path "$HOME/Documents")" "${HOME:a}/Documents" "logical abs"
  assert_eq "$(_dnav_logical_path "")" "" "empty stays empty"
}

test_resolve_dir_climbs_missing() {
  local base="$DNAV_TEST_TMP/resolve" rc
  mkdir -p -- "$base/here"
  _dnav_resolve_dir "$base/here"
  rc=$?
  assert_eq "$rc" "0" "existing dir is ok"
  assert_eq "${REPLY:a}" "${base:a}/here" "keeps existing dir"
  _dnav_resolve_dir "$base/here/no/such"
  rc=$?
  assert_eq "$rc" "1" "missing path is invalid"
  assert_eq "${REPLY:a}" "${base:a}/here" "lands on ancestor"
  _dnav_resolve_dir ""
  rc=$?
  assert_eq "$rc" "0" "empty path is PWD"
  assert_eq "${REPLY:a}" "${PWD:a}" "empty uses PWD"
}

test_status_label_is_top_layer() {
  _dnav_status_set error "Permission Denied: /root"
  assert_eq "$(_dnav_status_label)" "-- Permission Denied: /root " "prefix -- for readability"
  _dnav_status_clear
  assert_eq "$(_dnav_status_label)" "" "empty when cleared"
}

test_status_slot_set_and_expire() {
  DNAV_CFG_STATUS_TIMEOUT_MS=40
  _dnav_status_set error "Invalid Path"
  assert_eq "$_DNAV_STATUS_KIND" "error"
  assert_eq "$_DNAV_STATUS_TEXT" "Invalid Path"
  if _dnav_status_tick; then
    assert_eq "$_DNAV_STATUS_TEXT" "" "expired message clears"
  else
    _dnav_test_fail "status should expire after one 40ms tick"
  fi
  _dnav_status_set info "kept"
  DNAV_CFG_STATUS_TIMEOUT_MS=0
  _dnav_status_set info "sticky"
  assert_eq "$_DNAV_STATUS_LEFT" "-1" "timeout 0 disables auto-clear"
  if _dnav_status_tick; then
    _dnav_test_fail "sticky status should not expire"
  else
    _dnav_test_pass "sticky status stays"
  fi
  _dnav_status_clear
  DNAV_CFG_STATUS_TIMEOUT_MS=3000
}

test_dnav_help_lists_entry_points() {
  local got
  got="$(dnav -h)"
  assert_contains "$got" "Usage: dnav" "dnav --help starts with Usage"
  assert_contains "$got" "f, file" "help lists file entry"
  assert_contains "$got" "s, search" "help lists search entry"
  assert_contains "$got" "dconfig" "help lists dconfig"
  assert_contains "$got" "djump" "help lists djump"
  assert_contains "$got" "--reindex" "help lists --reindex"
  assert_contains "$got" "--from" "help lists --reindex --from"
  if [[ $got == *$'\e'* ]]; then
    _dnav_test_fail "dnav --help should be plain text"
  else
    _dnav_test_pass "dnav --help is pipe-friendly"
  fi
}

test_dhelp_lists_jumps_only() {
  local got
  got="$(dhelp)"
  assert_contains "$got" "dhome" "dhelp lists dhome"
  if [[ $got == *"Usage: djump"* || $got == *"usage: djump"* || $got == *"add LABEL"* ]]; then
    _dnav_test_fail "dhelp should not print djump usage"
  else
    _dnav_test_pass "dhelp is not djump usage"
  fi
  if [[ $got == *"open the folder navigator"* || $got == *"dnav --update"* ]]; then
    _dnav_test_fail "dhelp should not be the general command list"
  else
    _dnav_test_pass "dhelp is the jump list"
  fi
  if [[ $got == *$'\e'* ]]; then
    _dnav_test_fail "dhelp should be plain text"
  else
    _dnav_test_pass "dhelp is pipe-friendly"
  fi
}

test_djump_help_is_usage() {
  local got
  got="$(djump --help)"
  assert_contains "$got" "Usage: djump" "djump --help is usage"
  assert_contains "$got" "add LABEL" "covers add"
  assert_contains "$got" "edit LABEL" "covers edit"
  assert_contains "$got" "remove LABEL" "covers remove"
  assert_contains "$got" "dhelp" "mentions dhelp for the list"
  if [[ $got == *$'\e'* ]]; then
    _dnav_test_fail "djump --help should be plain text"
  else
    _dnav_test_pass "djump --help is pipe-friendly"
  fi
}

test_disp_w_and_fit() {
  assert_eq "$(_dnav_disp_w "ab")" "2" "ascii width"
  assert_eq "$(_dnav_cell_w "ab")" "5" "unlocked cell is label+3"
  assert_eq "$(_dnav_fit_end "abcdefghij" 5)" "…ghij" "fit_end keeps tail"
  assert_eq "$(_dnav_fit_start "abcdefghij" 5)" "abcd…" "fit_start keeps head"
  local w
  w="$(_dnav_disp_w "中")"
  if (( w == 2 )); then
    _dnav_test_pass "CJK ideograph is 2 columns"
    assert_eq "$(_dnav_cell_w "中")" "5" "CJK unlocked cell 2+3"
    assert_eq "$(_dnav_fit_end "中中中" 3)" "…中" "fit_end by display cols"
  elif (( w == 1 )); then
    _dnav_test_pass "CJK width is 1 on this locale"
  else
    _dnav_test_fail "unexpected CJK width $w"
  fi
}

test_public_commands_defined() {
  assert_fn dnav
  assert_fn dhelp
  assert_fn dconfig
  _dnav_load_module dnav-update
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
  _dnav_load_module dnav-update
  got="$(_dnav_update_repo)"
  assert_file "$got/zsh/dnav" "dnav --update locates repo with zsh/dnav"
  got="$(DNAV_UPDATE_FROM="$DNAV_REPO_ROOT" _dnav_update_repo)"
  assert_eq "${got:A}" "${DNAV_REPO_ROOT:A}" "DNAV_UPDATE_FROM wins"
}

test_record_dest_writes_file() {
  local f="$DNAV_TEST_TMP/result-dest"
  DNAV_RESULT_FILE=$f
  _dnav_record_dest "/tmp/dnav-dest"
  assert_eq "$(<$f)" "/tmp/dnav-dest" "record_dest writes path"
  DNAV_RESULT_FILE=""
}

test_posix_hook_defines_commands() {
  local out
  out="$(DNAV_DIR="$DNAV_ZSH_DIR" DNAV_CONFIG_DIR="$DNAV_TEST_CONFIG" bash -c '
    . "$1/shell/dnav.sh"
    command -v dnav >/dev/null && command -v djump >/dev/null && echo ok
  ' bash "$DNAV_REPO_ROOT")" || true
  assert_eq "$out" "ok" "posix hook defines dnav and djump"
}

test_sourced_dnav_does_not_run_tui() {
  local out
  out="$(zsh -f -c 'source "$1/dnav"; print -r -- still-here' zsh "$DNAV_ZSH_DIR")"
  assert_contains "$out" "still-here" "sourcing dnav does not start the TUI"
}

test_posix_hook_dnav_help() {
  local out
  out="$(DNAV_DIR="$DNAV_ZSH_DIR" bash -c '
    . "$1/shell/dnav.sh"
    dnav --help
  ' bash "$DNAV_REPO_ROOT" 2>&1)" || true
  assert_contains "$out" "dnav" "foreign dnav --help runs zsh -f"
}

test_resourcing_reloads_search_plugin() {
  _dsearch_start() { print -r -- STALE; }
  source "$DNAV_ZSH_DIR/dnav"
  if [[ ${functions[_dsearch_start]} == *STALE* ]]; then
    _dnav_test_fail "re-source left a stale _dsearch_start"
  else
    _dnav_test_pass "re-source refreshed dsearch"
  fi
}

test_maybe_ls_waits_after_bar() {
  emulate -L zsh
  local slept=0
  local save_ls="${DNAV_CFG_LS:-0}"
  local save_ls_dnav="${DNAV_CFG_LS_DNAV:--1}"
  local save_ms="${DNAV_CFG_LS_AFTER_MS:-0}"
  functions -c _dnav_sleep_ms _dnav_sleep_ms_orig
  DNAV_CFG_LS=1
  DNAV_CFG_LS_DNAV=1
  DNAV_CFG_LS_AFTER_MS=400
  _dnav_sleep_ms() { slept=$1 }
  _dnav_maybe_ls dnav >/dev/null
  unfunction _dnav_sleep_ms
  functions -c _dnav_sleep_ms_orig _dnav_sleep_ms
  unfunction _dnav_sleep_ms_orig
  DNAV_CFG_LS=$save_ls
  DNAV_CFG_LS_DNAV=$save_ls_dnav
  DNAV_CFG_LS_AFTER_MS=$save_ms
  assert_eq "$slept" "400" "ls waits ls_after_ms when ls is on"
}

test_maybe_ls_skips_wait_when_ls_off() {
  emulate -L zsh
  local slept=0
  local save_ls="${DNAV_CFG_LS:-0}"
  local save_ls_dnav="${DNAV_CFG_LS_DNAV:--1}"
  local save_ms="${DNAV_CFG_LS_AFTER_MS:-0}"
  functions -c _dnav_sleep_ms _dnav_sleep_ms_orig
  DNAV_CFG_LS=0
  DNAV_CFG_LS_DNAV=0
  DNAV_CFG_LS_AFTER_MS=400
  _dnav_sleep_ms() { slept=$1 }
  _dnav_maybe_ls dnav >/dev/null
  unfunction _dnav_sleep_ms
  functions -c _dnav_sleep_ms_orig _dnav_sleep_ms
  unfunction _dnav_sleep_ms_orig
  DNAV_CFG_LS=$save_ls
  DNAV_CFG_LS_DNAV=$save_ls_dnav
  DNAV_CFG_LS_AFTER_MS=$save_ms
  assert_eq "$slept" "0" "no wait when ls is off"
}

test_success_bar_sleeps_per_step() {
  emulate -L zsh
  local -i n=0
  local save_anim="${DNAV_CFG_SUCCESS_ANIM:-1}"
  local save_steps="${DNAV_CFG_SUCCESS_ANIM_STEPS:-8}"
  local save_ms="${DNAV_CFG_SUCCESS_ANIM_MS:-25}"
  local save_bar="${DNAV_CFG_SUCCESS_BAR:-1}"
  local save_bar_dnav="${DNAV_CFG_SUCCESS_BAR_DNAV:--1}"
  functions -c _dnav_sleep_ms _dnav_sleep_ms_orig
  DNAV_CFG_SUCCESS_ANIM=1
  DNAV_CFG_SUCCESS_ANIM_STEPS=5
  DNAV_CFG_SUCCESS_ANIM_MS=10
  DNAV_CFG_SUCCESS_BAR=1
  DNAV_CFG_SUCCESS_BAR_DNAV=1
  COLUMNS=80
  _dnav_sleep_ms() { n+=1 }
  _dnav_success_bar /tmp "" dnav >/dev/null
  unfunction _dnav_sleep_ms
  functions -c _dnav_sleep_ms_orig _dnav_sleep_ms
  unfunction _dnav_sleep_ms_orig
  DNAV_CFG_SUCCESS_ANIM=$save_anim
  DNAV_CFG_SUCCESS_ANIM_STEPS=$save_steps
  DNAV_CFG_SUCCESS_ANIM_MS=$save_ms
  DNAV_CFG_SUCCESS_BAR=$save_bar
  DNAV_CFG_SUCCESS_BAR_DNAV=$save_bar_dnav
  assert_eq "$n" "5" "success bar waits once per anim step"
}

test_sleep_ms_survives_sigchld() {
  emulate -L zsh
  zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null || true
  local t0 t1
  local -i elapsed
  [[ -n ${EPOCHREALTIME:-} ]] || {
    _dnav_test_pass "sleep_ms SIGCHLD check skipped (no EPOCHREALTIME)"
    return 0
  }
  t0=$EPOCHREALTIME
  ( /bin/sleep 0.02 ) &
  _dnav_sleep_ms 80
  t1=$EPOCHREALTIME
  elapsed=$(( (t1 - t0) * 1000 ))
  if (( elapsed >= 50 )); then
    _dnav_test_pass "sleep_ms held through SIGCHLD (${elapsed}ms)"
  else
    _dnav_test_fail "sleep_ms returned early: ${elapsed}ms"
  fi
  wait 2>/dev/null || true
}

test_syntax_zsh_scripts() {
  local f
  for f in dnav dfile djump dsearch dsearch-index dindexer dnav-about dnav-update; do
    if zsh -n "$DNAV_ZSH_DIR/$f" 2>/dev/null; then
      _dnav_test_pass "zsh -n $f"
    else
      _dnav_test_fail "zsh -n $f"
    fi
  done
}

run_test test_djump_lazy_until_available
run_test test_crawler_not_sourced_with_dnav
run_test test_about_lazy_until_ensure
run_test test_update_lazy_until_load
run_test test_zsh_stub_does_not_source_djump
run_test test_modules_available
run_test test_winch_helpers_exist
run_test test_resize_waits_for_steady_stty
run_test test_resize_chip_label_main
run_test test_resize_chip_label_about
run_test test_tui_below_dfile_browse_wipes_three
run_test test_abort_flag_helper
run_test test_resize_chip_label_search
run_test test_usable_from_spares_two
run_test test_term_cols_reads_columns_cache
run_test test_logical_path_no_symlink_resolve
run_test test_resolve_dir_climbs_missing
run_test test_status_slot_set_and_expire
run_test test_status_label_is_top_layer
run_test test_dnav_help_lists_entry_points
run_test test_dhelp_lists_jumps_only
run_test test_djump_help_is_usage
run_test test_disp_w_and_fit
run_test test_public_commands_defined
run_test test_dnav_dir_points_at_package
run_test test_config_dir_isolated
run_test test_update_repo_finds_source
run_test test_record_dest_writes_file
run_test test_posix_hook_defines_commands
run_test test_posix_hook_dnav_help
run_test test_sourced_dnav_does_not_run_tui
run_test test_resourcing_reloads_search_plugin
run_test test_maybe_ls_waits_after_bar
run_test test_maybe_ls_skips_wait_when_ls_off
run_test test_success_bar_sleeps_per_step
run_test test_sleep_ms_survives_sigchld
run_test test_syntax_zsh_scripts
dnav_test_finish
