#!/usr/bin/env zsh
# Config parse, truthy, colors, folders (zsh)
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/tests/lib/zsh_env.zsh"
dnav_test_setup_zsh

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
  assert_eq "$got" "$HOME" "expand ~"
  got="$(_dnav_expand_path '~/Documents')"
  assert_eq "$got" "$HOME/Documents" "expand ~/Documents"
}

test_color_num() {
  assert_eq "$(_dnav_color_num fg black)" "30" "fg black"
  assert_eq "$(_dnav_color_num bg cyan)" "46" "bg cyan"
  assert_eq "$(_dnav_color_num fg 31)" "31" "numeric passthrough"
}

test_seeded_config_loaded() {
  assert_eq "$DNAV_CFG_BRAND" "ZshTestNav" "brand from fixture"
  assert_eq "$DNAV_CFG_LS" "0" "ls_after off"
  assert_eq "$DNAV_CFG_SUCCESS_ANIM" "0" "success_anim off"
  assert_ge "$#DNAV_FOLDER_NAMES" 3 "folders loaded"
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
  assert_eq "$got" "$DNAV_TEST_CONFIG"
}

test_config_set_updates_and_appends() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
# keep this comment
brand = OldBrand
ls_after = 0
EOF
  _dnav_config_set brand NewBrand
  _dnav_config_set show_hidden 1
  _dnav_config_set dfile_sort_dirs hidden_first
  assert_file "$DNAV_TEST_CONFIG/config"
  local txt
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "brand = NewBrand" "replaces existing key"
  assert_contains "$txt" "show_hidden = 1" "appends missing key"
  assert_contains "$txt" "dfile_sort_dirs = hidden_first" "appends dfile_sort_dirs"
  assert_contains "$txt" "# keep this comment" "keeps comments"
  _dnav_config_load
  assert_eq "$DNAV_CFG_BRAND" "NewBrand" "reload sees written brand"
  assert_eq "$DNAV_CFG_SHOW_HIDDEN" "1" "reload sees written show_hidden"
  assert_eq "$DNAV_CFG_DFILE_SORT_DIRS" "hidden_first" "reload sees written sort"
}

test_folders_save_persists() {
  DNAV_FOLDER_NAMES=(Home Labs)
  DNAV_FOLDER_PATHS=("$HOME" "$HOME/Projects")
  _dnav_folders_save
  assert_file "$DNAV_TEST_CONFIG/folders"
  local txt
  txt="$(<"$DNAV_TEST_CONFIG/folders")"
  assert_contains "$txt" "Home" "writes Home"
  assert_contains "$txt" "Labs" "writes Labs"
  _dnav_config_load_folders "$DNAV_TEST_CONFIG/folders"
  assert_eq "${DNAV_FOLDER_NAMES[2]}" "Labs" "reload sees saved folder"
}

test_config_set_works_when_path_local_empty() {
  # zsh ties local path to PATH; Settings used to declare `local path` and
  # then mv/mkdir vanished. Simulate that caller.
  local path
  path=()
  _dnav_config_set brand PathSafe
  local txt
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "brand = PathSafe" "save survives empty local path"
}

test_config_set_creates_missing_file() {
  command rm -f -- "$DNAV_TEST_CONFIG/config"
  _dnav_config_set brand Created
  assert_file "$DNAV_TEST_CONFIG/config" "creates config if missing"
  local txt
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "brand = Created"
  _dnav_config_load
  assert_eq "$DNAV_CFG_BRAND" "Created"
}

test_config_merge_adds_missing_keeps_values() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
# keep me
brand = KeepBrand
ls_after = 1
show_hidden = 1
EOF
  local added txt
  added="$(_dnav_config_merge_defaults "$DNAV_TEST_CONFIG")"
  assert_gt "$added" 0 "adds missing keys"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "brand = KeepBrand" "keeps existing brand"
  assert_contains "$txt" "ls_after = 1" "keeps existing ls_after"
  assert_contains "$txt" "show_hidden = 1" "keeps existing show_hidden"
  assert_contains "$txt" "# keep me" "keeps comments"
  assert_contains "$txt" "dfile_jump_name_max = 20" "adds new key"
  assert_contains "$txt" "success_bar = 1" "adds success_bar"
  added="$(_dnav_config_merge_defaults "$DNAV_TEST_CONFIG")"
  assert_eq "$added" "0" "second merge is a no-op"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  local n
  n="$(print -r -- "$txt" | grep -c '^brand = ' || true)"
  assert_eq "$n" "1" "does not duplicate brand"
}

test_config_merge_treats_alias_as_present() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = KeepBrand
ls = 1
hidden = 1
fg = red
EOF
  local added txt
  added="$(_dnav_config_merge_defaults "$DNAV_TEST_CONFIG")"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  if [[ $txt == *$'\nls_after ='* ]]; then
    _dnav_test_fail "should not add ls_after when ls is set"
  else
    _dnav_test_pass "ls alias counts as ls_after"
  fi
  if [[ $txt == *$'\nshow_hidden ='* ]]; then
    _dnav_test_fail "should not add show_hidden when hidden is set"
  else
    _dnav_test_pass "hidden alias counts as show_hidden"
  fi
  if [[ $txt == *$'\ncolor_fg ='* ]]; then
    _dnav_test_fail "should not add color_fg when fg is set"
  else
    _dnav_test_pass "fg alias counts as color_fg"
  fi
  assert_gt "$added" 0 "still adds unrelated missing keys"
}

test_dfile_jump_name_max_config() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = ZshTestNav
dfile_jump_name_max = 12
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_DFILE_JUMP_NAME_MAX" "12" "parses dfile_jump_name_max"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = ZshTestNav
dfile_jump_name_max = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_DFILE_JUMP_NAME_MAX" "20" "rejects 0, keeps default"
}

run_test test_truthy
run_test test_expand_path_tilde
run_test test_color_num
run_test test_seeded_config_loaded
run_test test_reload_picks_up_edits
run_test test_folders_skip_about_help
run_test test_dconfig_path
run_test test_config_set_updates_and_appends
run_test test_folders_save_persists
run_test test_config_set_works_when_path_local_empty
run_test test_config_set_creates_missing_file
run_test test_config_merge_adds_missing_keeps_values
run_test test_config_merge_treats_alias_as_present
run_test test_dfile_jump_name_max_config
dnav_test_finish
