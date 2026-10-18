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
  assert_eq "$DNAV_CFG_LS_AFTER_MS" "0" "ls_after_ms default 0"
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "none" "shift_enter default none"
  assert_eq "$DNAV_CFG_SHIFT_BAR" "0" "shift_enter_bar default off"
  assert_eq "$DNAV_CFG_SUCCESS_ANIM" "0" "success_anim off"
  assert_eq "$DNAV_CFG_INDEX_AUTO" "1" "index_auto default on"
  assert_eq "$DNAV_CFG_INDEX_WHEN" "open" "index_when default open"
  assert_eq "$DNAV_CFG_INDEX_TTL_HOURS" "24" "index_ttl_hours default 24"
  assert_ge "$#DNAV_FOLDER_NAMES" 3 "folders loaded"
}

test_index_config_keys() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = IdxCfg
index_auto = 0
index_when = search
index_ttl_hours = 6
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_INDEX_AUTO" "0" "index_auto off"
  assert_eq "$DNAV_CFG_INDEX_WHEN" "search" "index_when search"
  assert_eq "$DNAV_CFG_INDEX_TTL_HOURS" "6" "index_ttl_hours 6"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
auto_index = yes
index_on = s
index_ttl = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_INDEX_AUTO" "1" "auto_index alias"
  assert_eq "$DNAV_CFG_INDEX_WHEN" "search" "index_on s alias"
  assert_eq "$DNAV_CFG_INDEX_TTL_HOURS" "0" "index_ttl alias"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
index_file = ~/my-dirs
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_INDEX_FILE" "~/my-dirs" "index_file path"
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
  assert_contains "$txt" "# dfile Jump to: folder name max (cuts the end)" "notes Jump to: max"
  assert_contains "$txt" "success_bar = 1" "adds success_bar"
  assert_contains "$txt" "# Cyan path bar after select (0 = hide)" "notes success_bar"
  assert_contains "$txt" "ls_after_ms = 0" "adds ls_after_ms"
  assert_contains "$txt" "shift_enter = none" "adds shift_enter"
  assert_contains "$txt" "shift_enter_bar = 0" "adds shift_enter_bar"
  assert_contains "$txt" "# Shift+Enter on the bar: none, ls, or dls" "notes shift_enter"
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

test_config_merge_notes_bare_existing_keys() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = KeepBrand
# added by dupdate (previous values were kept)
full_redraw = 1
EOF
  _dnav_config_merge_defaults "$DNAV_TEST_CONFIG" >/dev/null
  local txt
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "brand = KeepBrand" "keeps brand value"
  assert_contains "$txt" "full_redraw = 1" "keeps full_redraw value"
  assert_contains "$txt" "# Brand chip label on the main bar" "notes brand"
  assert_contains "$txt" "# 1 = full line redraw every move; 0 = partial chip repaint" "notes full_redraw"
}

test_strip_comment_keeps_hash_in_value() {
  assert_eq "$(_dnav_strip_comment 'brand = Foo#Bar')" "brand = Foo#Bar" "hash in value"
  assert_eq "$(_dnav_trim "$(_dnav_strip_comment 'brand = Foo # trailing')")" "brand = Foo" "space-hash is comment"
  assert_eq "$(_dnav_trim "$(_dnav_strip_comment '  # whole line')")" "" "indented comment"
  assert_eq "$(_dnav_strip_comment 'Hashy  /tmp/proj#2')" "Hashy  /tmp/proj#2" "hash in path"
}

test_config_brand_with_hash() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = Foo#Bar
ls_after = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_BRAND" "Foo#Bar" "brand keeps #"
}

test_folders_hash_in_path() {
  mkdir -p -- "$DNAV_TEST_TMP/proj#2"
  cat > "$DNAV_TEST_CONFIG/folders" <<EOF
Home        ~
Hashy       $DNAV_TEST_TMP/proj#2
EOF
  _dnav_config_load_folders "$DNAV_TEST_CONFIG/folders"
  local i found=0
  for (( i=1; i <= $#DNAV_FOLDER_NAMES; i++ )); do
    if [[ ${DNAV_FOLDER_NAMES[i]} == Hashy ]]; then
      found=1
      assert_eq "${DNAV_FOLDER_PATHS[i]}" "$DNAV_TEST_TMP/proj#2" "folder path keeps #"
    fi
  done
  (( found )) || _dnav_test_fail "Hashy folder not loaded"
}

test_config_load_under_extended_glob() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = Ext#Glob
ls_after = 0
EOF
  setopt extended_glob
  _dnav_config_load
  unsetopt extended_glob
  assert_eq "$DNAV_CFG_BRAND" "Ext#Glob" "load under EXTENDED_GLOB"
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

test_seed_folders_are_generic() {
  local dir="$DNAV_TEST_TMP/freshseed" txt
  mkdir -p -- "$dir"
  _dnav_config_seed "$dir"
  txt="$(<"$dir/folders")"
  assert_contains "$txt" "Home" "seeds Home"
  assert_contains "$txt" "Docs" "seeds Docs"
  assert_contains "$txt" "Down" "seeds Down"
  assert_contains "$txt" "Config" "seeds Config"
  if [[ $txt == *EbSync* || $txt == *Eb_Transfer* ]]; then
    _dnav_test_fail "seed folders should not include EbSync"
  else
    _dnav_test_pass "no personal EbSync row"
  fi
  txt="$(<"$dir/jumps")"
  if [[ $txt == *Eb_Transfer* || $txt == *$'\neb '* ]]; then
    _dnav_test_fail "seed jumps should not include eb"
  else
    _dnav_test_pass "no personal eb jump"
  fi
}

test_schema_canon_and_aliases() {
  assert_eq "$(_dnav_config_canon_key ls)" "ls_after" "ls → ls_after"
  assert_eq "$(_dnav_config_canon_key ls_delay)" "ls_after_ms" "ls_delay → ls_after_ms"
  assert_eq "$(_dnav_config_canon_key fg)" "color_fg" "fg → color_fg"
  assert_eq "$(_dnav_config_canon_key auto_index)" "index_auto" "auto_index → index_auto"
  local n
  n="$(_dnav_config_key_note ls_after)"
  assert_contains "$n" "ls -a after" "schema note for ls_after"
}

test_seed_does_not_clobber_existing() {
  local txt
  print -r -- "brand = KeepMe" > "$DNAV_TEST_CONFIG/config"
  print -r -- "Home  ~" > "$DNAV_TEST_CONFIG/folders"
  _dnav_config_seed "$DNAV_TEST_CONFIG"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_eq "$txt" "brand = KeepMe" "seed leaves existing config"
  txt="$(<"$DNAV_TEST_CONFIG/folders")"
  assert_eq "$txt" "Home  ~" "seed leaves existing folders"
}

run_test test_truthy
run_test test_expand_path_tilde
run_test test_color_num
run_test test_seeded_config_loaded
run_test test_schema_canon_and_aliases
run_test test_index_config_keys
run_test test_reload_picks_up_edits
run_test test_folders_skip_about_help
run_test test_dconfig_path
run_test test_config_set_updates_and_appends
run_test test_folders_save_persists
run_test test_config_set_works_when_path_local_empty
run_test test_config_set_creates_missing_file
run_test test_config_merge_adds_missing_keeps_values
run_test test_config_merge_treats_alias_as_present
run_test test_config_merge_notes_bare_existing_keys
run_test test_strip_comment_keeps_hash_in_value
run_test test_config_brand_with_hash
run_test test_folders_hash_in_path
run_test test_config_load_under_extended_glob
run_test test_dfile_jump_name_max_config
test_inaccessible_config_keys() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = ZshTestNav
inaccessible_color = yellow
inaccessible_icon = 0
status_timeout_ms = 1500
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_INACC_COLOR" "33" "yellow → 33"
  assert_eq "$DNAV_CFG_INACC_ICON" "0" "icon off"
  assert_eq "$DNAV_CFG_STATUS_TIMEOUT_MS" "1500" "timeout parsed"
}

test_ls_after_ms_config() {
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = DelayCfg
ls_after_ms = 400
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_LS_AFTER_MS" "400" "ls_after_ms parsed"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
ls_delay = 250
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_LS_AFTER_MS" "250" "ls_delay alias"
}

test_ls_after_dls_config() {
  local txt
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = LsCfg
ls_after = dls
ls_after_dnav = inherit
ls_after_djump = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_LS" "dls" "ls_after dls"
  assert_eq "$DNAV_CFG_LS_DNAV" "-1" "dnav inherit stays -1"
  assert_eq "$DNAV_CFG_LS_DJUMP" "0" "djump off"
  assert_eq "$(_dnav_ls_mode dnav)" "dls" "dnav inherits dls"
  assert_eq "$(_dnav_ls_mode djump)" "off" "djump override is off"
  assert_ok _dnav_want_ls dnav
  assert_fail _dnav_want_ls djump

  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
ls_after = ls
ls_after_dnav = dls
ls_after_djump = ls
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_LS" "1" "ls_after ls stores 1"
  assert_eq "$DNAV_CFG_LS_DNAV" "dls" "dnav override is dls"
  assert_eq "$DNAV_CFG_LS_DJUMP" "1" "djump override is ls"
  assert_eq "$(_dnav_ls_mode dnav)" "dls" "dnav uses its own dls"
  assert_eq "$(_dnav_ls_mode djump)" "ls" "djump uses ls"
  assert_eq "$(_dnav_ls_label "$DNAV_CFG_LS")" "ls" "1 is labeled ls"
  assert_eq "$(_dnav_ls_label "$DNAV_CFG_LS_DNAV")" "dls" "dls is labeled dls"
  assert_eq "$(_dnav_ls_label "$DNAV_CFG_LS_DJUMP")" "ls" "stored 1 is labeled ls"

  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
ls_after = 1
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_LS" "1" "ls_after 1 still means ls"
  assert_eq "$DNAV_CFG_LS_DNAV" "-1" "missing override inherits"
  assert_eq "$(_dnav_ls_mode djump)" "ls" "djump inherits ls"

  DNAV_CFG_LS=0
  _dnav_ls_cycle ls_after
  assert_eq "$DNAV_CFG_LS" "1" "cycle off to ls"
  _dnav_ls_cycle ls_after
  assert_eq "$DNAV_CFG_LS" "dls" "cycle ls to dls"
  _dnav_ls_cycle ls_after
  assert_eq "$DNAV_CFG_LS" "0" "cycle dls to off"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "ls_after = 0" "cycle writes ls_after"

  DNAV_CFG_LS_DJUMP=-1
  _dnav_ls_cycle ls_after_djump
  assert_eq "$DNAV_CFG_LS_DJUMP" "1" "djump cycle inherit to ls"
  _dnav_ls_cycle ls_after_djump
  assert_eq "$DNAV_CFG_LS_DJUMP" "dls" "djump cycle ls to dls"
  _dnav_ls_cycle ls_after_djump
  assert_eq "$DNAV_CFG_LS_DJUMP" "0" "djump cycle dls to off"
  _dnav_ls_cycle ls_after_djump
  assert_eq "$DNAV_CFG_LS_DJUMP" "-1" "djump cycle off to inherit"
  txt="$(<"$DNAV_TEST_CONFIG/config")"
  assert_contains "$txt" "ls_after_djump = inherit" "cycle writes inherit"

  DNAV_CFG_LS=0
  DNAV_CFG_LS_DNAV=-1
  DNAV_CFG_LS_DJUMP=-1
}

test_shift_enter_config() {
  local txt n dir tok
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
brand = ShiftCfg
ls_after = 0
shift_enter = dls
shift_enter_bar = 1
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "dls" "shift_enter dls"
  assert_eq "$DNAV_CFG_SHIFT_BAR" "1" "shift_enter_bar on"
  assert_eq "$DNAV_CFG_LS" "0" "enter listing stays off"
  assert_eq "$(_dnav_ls_mode dnav)" "off" "enter ignores shift_enter"
  assert_eq "$(_dnav_ls_mode dnav enter)" "off" "explicit enter ignores shift_enter"
  assert_eq "$(_dnav_ls_mode dnav shift-enter)" "dls" "shift-enter uses shift_enter"
  assert_fail _dnav_want_ls dnav

  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
shift_enter = ls
shift_enter_bar = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "ls" "shift_enter ls stays the word ls"
  assert_eq "$DNAV_CFG_SHIFT_BAR" "0" "shift_enter_bar off"
  assert_eq "$(_dnav_ls_mode dnav shift-enter)" "ls" "shift-enter ls"

  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
shift_enter = 1
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "ls" "shift_enter 1 means ls"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
shift_enter = off
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "none" "shift_enter off means none"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
shift_enter = 0
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "none" "shift_enter 0 means none"
  cat > "$DNAV_TEST_CONFIG/config" <<'EOF'
shift_enter = garbage
EOF
  _dnav_config_load
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "none" "shift_enter garbage means none"
  assert_eq "$(_dnav_ls_mode dnav shift-enter)" "off" "garbage shift-enter lists nothing"

  DNAV_CFG_LS=dls
  DNAV_CFG_LS_DNAV=-1
  DNAV_CFG_SHIFT_ENTER=none
  assert_eq "$(_dnav_ls_mode dnav)" "dls" "enter still follows ls_after"
  assert_eq "$(_dnav_ls_mode djump shift-enter)" "off" "djump shift-enter is still shift_enter"

  source "$DNAV_ZSH_DIR/dnav-about"
  DNAV_CFG_SHIFT_ENTER=none
  _dnav_settings_apply_key enum shift_enter
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "ls" "settings cycles none to ls"
  _dnav_settings_apply_key enum shift_enter
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "dls" "settings cycles ls to dls"
  _dnav_settings_apply_key enum shift_enter
  assert_eq "$DNAV_CFG_SHIFT_ENTER" "none" "settings cycles dls to none"
  DNAV_CFG_SHIFT_BAR=0
  _dnav_settings_apply_key toggle shift_enter_bar
  assert_eq "$DNAV_CFG_SHIFT_BAR" "1" "settings toggles the shift bar"

  n="$(_dnav_config_key_note shift_enter)"
  assert_contains "$n" "none, ls, or dls" "schema note for shift_enter"
  if [[ $n == *'|'* ]]; then
    _dnav_test_fail "shift_enter note contains a pipe"
  else
    _dnav_test_pass "shift_enter note has no pipe"
  fi
  n="$(_dnav_config_key_note ls_after)"
  assert_contains "$n" "ls -a after" "ls_after note unchanged"

  for tok in A B C D H F '3~' '1~' '13;2u' '13;2;1u' '13;2:1u' '13:10;2u' '13;130u' '13;66u' '13;194u' '10;130u' '27;2;13~' '27;2;13;1~' '27;130;13~' '27u' '27;2u' '27;2:1u' '27;129u' '27;2;27~' '99;5u' '99;5:1u' '99;133u' '27;5;99~' '27;133;99~' '13;5u' '99~' '1;2A' '1;130A'; do
    _dnav_match_csi "$tok"
    case $tok in
      A) assert_eq "$REPLY" "up" "csi A is up" ;;
      B) assert_eq "$REPLY" "down" "csi B is down" ;;
      C) assert_eq "$REPLY" "right" "csi C is right" ;;
      D) assert_eq "$REPLY" "left" "csi D is left" ;;
      H) assert_eq "$REPLY" "home" "csi H is home" ;;
      F) assert_eq "$REPLY" "end" "csi F is end" ;;
      3~) assert_eq "$REPLY" "delete" "csi delete" ;;
      1~) assert_eq "$REPLY" "home" "csi home" ;;
      13\;2u|13\;2\;1u|13\;2:1u|13:10\;2u|13\;130u|13\;66u|13\;194u|10\;130u|27\;2\;13~|27\;2\;13\;1~|27\;130\;13~) assert_eq "$REPLY" "shift-enter" "csi $tok is shift-enter" ;;
      27u|27\;2u|27\;2:1u|27\;129u|27\;2\;27~) assert_eq "$REPLY" "esc" "csi $tok is escape" ;;
      99\;5u|99\;5:1u|99\;133u|27\;5\;99~|27\;133\;99~) assert_eq "$REPLY" "ctrl-c" "csi $tok is ctrl-c" ;;
      13\;5u|99~) assert_eq "$REPLY" "ignore" "csi $tok is not shift-enter" ;;
      1\;2A|1\;130A) assert_eq "$REPLY" "up" "shift-up stays up" ;;
      *) _dnav_test_fail "untested csi $tok" ;;
    esac
  done

  _dnav_classify_key $'\r'
  assert_eq "$REPLY" "enter" "carriage return is enter"
  _dnav_classify_key $'\n'
  assert_eq "$REPLY" "shift-enter" "newline is shift-enter"

  dir="$DNAV_TEST_TMP/shiftseed"
  mkdir -p -- "$dir"
  _dnav_config_seed "$dir"
  txt="$(<"$dir/config")"
  assert_contains "$txt" "shift_enter = none" "seed writes shift_enter"
  assert_contains "$txt" "shift_enter_bar = 0" "seed writes shift_enter_bar"

  DNAV_CFG_LS=0
  DNAV_CFG_LS_DNAV=-1
  DNAV_CFG_LS_DJUMP=-1
  DNAV_CFG_SHIFT_ENTER=none
  DNAV_CFG_SHIFT_BAR=0
}

run_test test_seed_folders_are_generic
run_test test_inaccessible_config_keys
run_test test_ls_after_ms_config
run_test test_ls_after_dls_config
run_test test_shift_enter_config
run_test test_seed_does_not_clobber_existing
dnav_test_finish
