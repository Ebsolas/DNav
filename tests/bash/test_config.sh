#!/usr/bin/env bash
# Config parse, truthy, colors, folders
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/bash_env.sh
source "$ROOT/tests/lib/bash_env.sh"

dnav_test_setup_bash

test_truthy() {
  assert_ok _dnav_truthy 1
  assert_ok _dnav_truthy true
  assert_ok _dnav_truthy YES
  assert_ok _dnav_truthy on
  assert_fail _dnav_truthy 0
  assert_fail _dnav_truthy false
  assert_fail _dnav_truthy ""
  assert_fail _dnav_truthy no
}

test_expand_path_tilde() {
  local got
  got="$(_dnav_expand_path '~')"
  got="${got%$'\n'}"
  assert_eq "$got" "$HOME" "expand ~"
  got="$(_dnav_expand_path '~/Documents')"
  got="${got%$'\n'}"
  assert_eq "$got" "$HOME/Documents" "expand ~/Documents"
}

test_color_num() {
  assert_eq "$(_dnav_color_num fg black)" "30" "fg black"
  assert_eq "$(_dnav_color_num bg cyan)" "46" "bg cyan"
  assert_eq "$(_dnav_color_num fg 31)" "31" "numeric passthrough"
}

test_seeded_config_loaded() {
  assert_eq "$DNAV_CFG_BRAND" "TestNav" "brand from fixture"
  assert_eq "$DNAV_CFG_LS" "0" "ls_after off"
  assert_eq "$DNAV_CFG_SUCCESS_ANIM" "0" "success_anim off in fixture"
  assert_ge "${#DNAV_FOLDER_NAMES[@]}" 3 "folders loaded"
}

test_reload_picks_up_edits() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = red
color_bg = blue
brand = Reloaded
ls_after = 1
show_hidden = 1
success_anim = 0
full_redraw = 1
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_BRAND" "Reloaded"
  assert_eq "$DNAV_CFG_LS" "1"
  assert_eq "$DNAV_CFG_SHOW_HIDDEN" "1"
  assert_eq "$DNAV_CFG_FULL_REDRAW" "1"
  # color names resolved to numbers
  assert_eq "$DNAV_CFG_COLOR_FG" "31" "red -> 31"
  assert_eq "$DNAV_CFG_COLOR_BG" "44" "blue -> 44 (bg)"
}

test_folders_skip_about_help() {
  cat > "$DNAV_TEST_CONFIG/folders" <<'EOF'
Home        ~
About       /tmp
Help        /tmp
Projects    ~/Projects
EOF
  _dnav_config_load_folders "$DNAV_TEST_CONFIG/folders"
  local joined=" ${DNAV_FOLDER_NAMES[*]} "
  assert_contains "$joined" " Home " "keeps Home"
  assert_contains "$joined" " Projects " "keeps Projects"
  if [[ $joined == *" About "* || $joined == *" Help "* ]]; then
    _dnav_test_fail "About/Help should be skipped from folders file"
  else
    _dnav_test_pass "skips About and Help rows"
  fi
}

test_dconfig_path() {
  local got
  got="$(dconfig -p)"
  got="${got%$'\n'}"
  assert_eq "$got" "$DNAV_TEST_CONFIG"
}

run_test test_truthy
run_test test_expand_path_tilde
run_test test_color_num
run_test test_seeded_config_loaded
run_test test_reload_picks_up_edits
run_test test_folders_skip_about_help
run_test test_dconfig_path
dnav_test_finish
