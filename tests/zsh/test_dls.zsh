#!/usr/bin/env zsh
# dls grid helpers. No raw terminal.
emulate -L zsh
setopt no_unset no_extended_glob
setopt no_err_return

ROOT="${0:A:h:h:h}"
source "$ROOT/tests/lib/zsh_assert.zsh"
source "$ROOT/zsh/dls"

DLS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nav-dls.XXXXXX")"
trap 'chmod -R u+rwx -- "$DLS_TMP" 2>/dev/null || true; rm -rf -- "$DLS_TMP"' EXIT

test_dls_source_is_standalone() {
  assert_fn dls
  assert_fn _dls_list
  assert_fn _dls_layout
  assert_fn _dls_move
  if (( $+functions[_dnav_draw] || $+functions[_dfile_enter] || $+functions[_dsearch_rank_phases] )); then
    _dnav_test_fail "sourcing dls pulled in dnav"
  else
    _dnav_test_pass "dls does not define dnav functions"
  fi
}

test_dls_layout_and_move() {
  local idx
  _DLS_NAMES=(abcdefgh ijklmnop qrstuvwx yzabcdef 12345678 abcdefgh ijklmnop qrstuvwx yzabcdef 12345678)
  _DLS_ISDIR=(0 0 0 0 0 0 0 0 0 0)
  _dls_layout 40
  assert_eq "$_DLS_COLW" "8" "column width is the longest name"
  assert_eq "$_DLS_NCOLS" "4" "40 columns fit 4 names of width 8"

  idx=0
  _dls_move $idx l 4 10; idx=$REPLY
  _dls_move $idx l 4 10; idx=$REPLY
  _dls_move $idx j 4 10; idx=$REPLY
  _dls_move $idx h 4 10; idx=$REPLY
  _dls_move $idx k 4 10; idx=$REPLY
  assert_eq "$idx" "1" "l l j h k lands on the second cell"

  _dls_move 0 h 4 10
  assert_eq "$REPLY" "0" "h on the left edge stays"
  _dls_move 0 k 4 10
  assert_eq "$REPLY" "0" "k on the top row stays"
  _dls_move 3 l 4 10
  assert_eq "$REPLY" "3" "l at the end of a row stays"
  _dls_move 9 j 4 10
  assert_eq "$REPLY" "9" "j on the last row stays"
  _dls_move 9 l 4 10
  assert_eq "$REPLY" "9" "l on a short row stays"

  _dls_scroll 9 4 10 2 0
  assert_eq "$REPLY" "1" "window follows the highlight down"
  _dls_scroll 0 4 10 2 1
  assert_eq "$REPLY" "0" "window follows the highlight up"
}

test_dls_scroll_follows_move() {
  local idx scroll ncols n body i row
  idx=0
  scroll=0
  ncols=1
  n=30
  body=5
  for (( i = 0; i < 20; i++ )); do
    _dls_move $idx j $ncols $n
    idx=$REPLY
    _dls_scroll $idx $ncols $n $body $scroll
    scroll=$REPLY
    row=$(( idx / ncols ))
    if (( row < scroll || row >= scroll + body )); then
      _dnav_test_fail "row $row left the window at $scroll"
      return
    fi
  done
  assert_eq "$idx" "20" "twenty steps down lands on that row"
  assert_eq "$scroll" "16" "window keeps the row on the last visible line"
  for (( i = 0; i < 30; i++ )); do
    _dls_move $idx k $ncols $n
    idx=$REPLY
    _dls_scroll $idx $ncols $n $body $scroll
    scroll=$REPLY
    row=$(( idx / ncols ))
    if (( row < scroll || row >= scroll + body )); then
      _dnav_test_fail "row $row left the window while moving up"
      return
    fi
  done
  assert_eq "$idx" "0" "k climbs back to the first row"
  assert_eq "$scroll" "0" "window follows back to the top"

  idx=0
  scroll=0
  ncols=4
  n=40
  body=3
  for (( i = 0; i < 12; i++ )); do
    _dls_move $idx j $ncols $n
    idx=$REPLY
    _dls_scroll $idx $ncols $n $body $scroll
    scroll=$REPLY
    row=$(( idx / ncols ))
    if (( row < scroll || row >= scroll + body )); then
      _dnav_test_fail "grid row $row left the window at $scroll"
      return
    fi
  done
  _dnav_test_pass "a tall grid stays under the highlight"
}

test_dls_place_fits_the_screen() {
  _dls_place 10 10 10
  assert_eq "$REPLY" "1" "a full screen starts at the top row"
  assert_eq "$REPLY2" "9" "a full screen scrolls the prompt up"
  _dls_place 10 10 5
  assert_eq "$REPLY" "6" "a short list keeps the bottom rows"
  assert_eq "$REPLY2" "4" "a short list scrolls only as far as it needs"
  _dls_place 10 4 3
  assert_eq "$REPLY" "4" "a list that fits stays on the cursor row"
  assert_eq "$REPLY2" "0" "a list that fits does not scroll the terminal"
  _dls_place 10 8 5
  assert_eq "$REPLY" "6" "a list below the cursor moves up to fit"
  assert_eq "$REPLY2" "4" "moving up prints the newlines that make room"
  _dls_place 10 3 10
  assert_eq "$REPLY" "1" "a tall list from mid-screen uses the top"
  assert_eq "$REPLY2" "9" "a tall list scrolls enough to fill the screen"

  _dls_expand_place 40 37 40
  assert_eq "$REPLY" "1" "opening a tall directory grows to the top"
  assert_eq "$REPLY2" "36" "growing scrolls the existing block upward"
  _dls_expand_place 40 10 4
  assert_eq "$REPLY" "10" "a shorter directory keeps its row"
  assert_eq "$REPLY2" "0" "a shorter directory does not scroll"

  _dls_view_cap 24 1
  assert_eq "$REPLY" "23" "one row stays free for the status line"
  assert_eq "$REPLY2" "1" "a normal screen shows the status line"
  _dls_view_cap 10 6
  assert_eq "$REPLY" "4" "the body is the rows from the origin, minus status"
  assert_eq "$REPLY2" "1" "a block not at the top still has a status line"
  _dls_view_cap 1 1
  assert_eq "$REPLY" "1" "a one-row screen still shows a name"
  assert_eq "$REPLY2" "0" "a one-row screen drops the status line"
}

test_dls_cell_stays_within_width() {
  setopt localoptions extended_glob
  local cell plain w
  _dls_config_defaults
  _DLS_LONG=1
  _DLS_NAMES=(verylongname)
  _DLS_KIND=(file)
  _DLS_LINK=(0)
  _DLS_EXEC=(0)
  _DLS_SIZE=(999999)
  _DLS_MODE=(33188)
  _DLS_NLINK=(1)
  _DLS_UID=(0)
  _DLS_GID=(0)
  _DLS_MTIME=(0)
  _DLS_ATIME=(0)
  _DLS_CTIME=(0)
  _DLS_BIRTH=(0)
  _DLS_TARGET=("")
  _DLS_INODE=0
  _DLS_BLOCKS=0
  _dls_measure
  cell="$(_dls_cell 1 20 0)"
  plain="${cell//$'\e'\[[0-9;]#m/}"
  w="$(_dls_disp_w "$plain")"
  if (( w > 20 )); then
    _dnav_test_fail "long cell is $w columns, wider than 20: $plain"
  else
    _dnav_test_pass "long cell stays within the screen width"
  fi
  _dls_config_defaults
}

test_dls_cached_line_matches_cell() {
  local root="$DLS_TMP/cache" i got want
  mkdir -p -- "$root/dir"
  : > "$root/file"
  _dls_config_defaults
  _DLS_COLS=80
  _dls_list "$root" 0
  _dls_prepare
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    _dls_line_set "$i" 0
    got=$REPLY
    want="$(_dls_cell "$i" "$_DLS_COLW" 0)"
    if [[ $got != "$want" ]]; then
      _dnav_test_fail "cached ${_DLS_NAMES[i]} differs from the cell"
      _dls_config_defaults
      return
    fi
    _dls_line_set "$i" 1
    got=$REPLY
    want="$(_dls_cell "$i" "$_DLS_COLW" 1)"
    if [[ $got != "$want" ]]; then
      _dnav_test_fail "selected cached ${_DLS_NAMES[i]} differs from the cell"
      _dls_config_defaults
      return
    fi
  done
  _dnav_test_pass "cached grid lines match the cell"

  _DLS_LONG=1
  _DLS_SIG=""
  _dls_prepare
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    _dls_line_set "$i" 0
    got=$REPLY
    want="$(_dls_cell "$i" "$_DLS_COLW" 0)"
    if [[ $got != "$want" ]]; then
      _dnav_test_fail "cached long ${_DLS_NAMES[i]} differs from the cell"
      _dls_config_defaults
      return
    fi
    _dls_line_set "$i" 1
    got=$REPLY
    want="$(_dls_cell "$i" "$_DLS_COLW" 1)"
    if [[ $got != "$want" ]]; then
      _dnav_test_fail "selected long ${_DLS_NAMES[i]} differs from the cell"
      _dls_config_defaults
      return
    fi
  done
  _dnav_test_pass "cached long lines match the cell"
  _dls_config_defaults
}

test_dls_list_sort_and_hidden() {
  local root="$DLS_TMP/root" joined flags
  mkdir -p -- "$root/Dir" "$root/real" "$root/.hid"
  : > "$root/b"
  : > "$root/A"
  : > "$root/c"
  : > "$root/.secret"
  ln -s real "$root/link"

  _dls_list "$root" 0
  joined="${(j: :)_DLS_NAMES}"
  flags="${(j: :)_DLS_ISDIR}"
  assert_eq "$joined" "A b c Dir link real" "case-insensitive order, dots hidden"
  assert_eq "$flags" "0 0 0 1 1 1" "directories and links to them are flagged"
  if [[ $joined == *.* ]]; then
    _dnav_test_fail "dot names leaked into the default listing"
  else
    _dnav_test_pass "dot names stay hidden"
  fi

  _dls_list "$root" 1
  joined="${(j: :)_DLS_NAMES}"
  local -a plain
  local i name
  plain=()
  for name in "${_DLS_NAMES[@]}"; do
    [[ $name == .* ]] && continue
    plain+=("$name")
  done
  assert_eq "${(j: :)plain}" "A b c Dir link real" "visible names keep their order"
  assert_contains "$joined" ".hid" "dot toggle shows hidden directory"
  assert_contains "$joined" ".secret" "dot toggle shows hidden file"
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if [[ ${_DLS_NAMES[i]} == .hid ]]; then
      assert_eq "${_DLS_ISDIR[i]}" "1" "hidden directory is flagged"
    elif [[ ${_DLS_NAMES[i]} == .secret ]]; then
      assert_eq "${_DLS_ISDIR[i]}" "0" "hidden file is not a directory"
    elif [[ ${_DLS_NAMES[i]} == . || ${_DLS_NAMES[i]} == .. ]]; then
      _dnav_test_fail ". or .. listed"
    fi
  done
  if [[ $joined == *'..'* ]]; then
    _dnav_test_fail ".. listed"
  else
    _dnav_test_pass ". and .. are not listed"
  fi
}

test_dls_enter_and_parent() {
  local root="$DLS_TMP/root" dest here
  _dls_list "$root" 0
  assert_eq "$(_dls_enter_kind 1)" "descend" "enter on a directory descends"
  assert_eq "$(_dls_enter_kind 0)" "stay" "enter on a file stays"
  dest="$(_dls_dir_at "$root" 3)"
  assert_eq "$dest" "$root/Dir" "directory index resolves to that folder"
  if _dls_dir_at "$root" 0 >/dev/null; then
    _dnav_test_fail "file index should not be a directory target"
  else
    _dnav_test_pass "file index is not a directory target"
  fi
  assert_eq "$(_dls_parent /)" "/" "parent of / is /"
  assert_eq "$(_dls_parent /tmp/foo)" "/tmp" "parent strips one segment"
  assert_eq "$(_dls_parent /tmp/)" "/" "trailing slash does not change the parent"

  here="$PWD"
  (
    _dls_open "$root/Dir" || exit 1
    [[ $PWD == "$root/Dir" ]] || exit 2
    (( _DLS_SEL == 0 )) || exit 3
    exit 0
  ) || {
    _dnav_test_fail "open does not land in the directory"
    return
  }
  _dnav_test_pass "open changes to the directory"
  assert_eq "$PWD" "$here" "open in a subshell does not move the caller"
}

test_dls_unreadable_keeps_listing() {
  local root="$DLS_TMP/root" before rc here
  mkdir -p -- "$root/locked"
  _dls_list "$root" 0
  before="${(j: :)_DLS_NAMES}"
  chmod 000 -- "$root/locked"
  here="$PWD"
  _dls_open "$root/locked"
  rc=$?
  assert_eq "$rc" "2" "unreadable directory is rejected"
  assert_eq "${(j: :)_DLS_NAMES}" "$before" "previous listing stays"
  assert_eq "$PWD" "$here" "failed open does not cd"
  assert_contains "$_DLS_ERR" "cannot read" "error names the failure"
  chmod u+rwx -- "$root/locked"
}

test_dls_fit_keeps_slash_inside_width() {
  local got w
  got="$(_dls_fit "abcdefghij" "/" 6)"
  w="$(_dls_disp_w "$got")"
  if (( w <= 6 && w > 0 )); then
    _dnav_test_pass "truncated directory cell fits"
  else
    _dnav_test_fail "truncated directory cell width=$w"
  fi
  if [[ $got == */ ]]; then
    _dnav_test_pass "truncated directory still ends with /"
  else
    _dnav_test_fail "missing slash on truncated directory (${(q)got})"
  fi
}

test_dls_stub_defines_dls_without_loading() {
  local cfg="$DLS_TMP/config" out
  mkdir -p -- "$cfg"
  print -r -- "ls /tmp" > "$cfg/jumps"
  out="$(
    DNAV_DIR="$ROOT/zsh" DNAV_CONFIG_DIR="$cfg" HOME="$HOME" zsh -f -c '
      emulate -L zsh
      source "$1/shell/dnav.zsh"
      (( $+functions[dls] )) || exit 2
      (( $+functions[_dls_list] )) && exit 3
      body="$(functions dls)"
      [[ $body == *source* ]] || exit 4
      [[ $body == *_djump_goto* ]] && exit 5
      print -r -- ok
    ' zsh "$ROOT"
  )" || {
    _dnav_test_fail "stub source failed (rc=$?)"
    return
  }
  assert_eq "$out" "ok" "stub binds dls and does not source it"
}

_dls_kind_named() {
  local want="$1" i
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if [[ ${_DLS_NAMES[i]} == "$want" ]]; then
      print -rn -- "${_DLS_KIND[i]}"
      return 0
    fi
  done
  return 1
}

test_dls_missing_rc_keeps_defaults() {
  local save_cfg="${DLS_CONFIG:-}" save_xdg="${XDG_CONFIG_HOME:-}"
  unset DLS_CONFIG
  export XDG_CONFIG_HOME="$DLS_TMP/no-xdg"
  _DLS_CONFIG_ARG=""
  _DLS_RC_WARN=()
  _dls_config_load
  assert_eq "$_DLS_SORT" "name" "missing rc keeps name order"
  assert_eq "$_DLS_SORT_DIRS" "mixed" "missing rc mixes files and directories"
  assert_eq "$_DLS_SORT_DOTS" "mixed" "missing rc does not group dot names"
  assert_eq "$_DLS_SHOW_HIDDEN" "0" "missing rc hides dotfiles"
  assert_eq "$_DLS_AUTO_CLS" "off" "missing rc leaves auto clear off"
  assert_eq "$_DLS_SHIFT_LS" "off" "missing rc lists nothing after shift-enter"
  assert_eq "${#_DLS_RC_WARN}" "0" "missing rc is silent"
  assert_eq "$(_dls_sort_label)" "name" "label is the sort mode"
  [[ -n $save_cfg ]] && export DLS_CONFIG="$save_cfg"
  [[ -n $save_xdg ]] && export XDG_CONFIG_HOME="$save_xdg"
  _dls_config_defaults
}

test_dls_sort_orders() {
  local dir="$DLS_TMP/sort" joined
  mkdir -p -- "$dir/m"
  : > "$dir/a"
  : > "$dir/b"
  : > "$dir/c"
  : > "$dir/a.z"
  : > "$dir/b.txt"
  : > "$dir/d.TXT"
  : > "$dir/f1"
  : > "$dir/f2"
  : > "$dir/f10"
  printf 'a' > "$dir/small"
  printf 'aaaaaa' > "$dir/big"
  touch -d '2020-01-01 00:00:00' "$dir/old" || touch -t 202001010000 "$dir/old"
  touch -d '2024-06-01 00:00:00' "$dir/new" || touch -t 202406010000 "$dir/new"

  _dls_config_defaults
  # Empty suffix first, then txt (b before d), then z.
  _DLS_NAMES=(a.z b.txt c d.TXT)
  _DLS_ISDIR=(0 0 0 0)
  _DLS_LINK=(0 0 0 0)
  _DLS_EXEC=(0 0 0 0)
  _DLS_SIZE=(0 0 0 0)
  _DLS_MTIME=(0 0 0 0)
  _DLS_KIND=(file file file file)
  _DLS_SORT=ext
  _DLS_SORT_DIRS=mixed
  _DLS_SORT_REVERSE=0
  _DLS_SORT_CASE=ignore
  _dls_apply_sort
  assert_eq "${(j: :)_DLS_NAMES}" "c b.txt d.TXT a.z" "ext order is suffix then name"

  _DLS_NAMES=(f10 f2 f1)
  _DLS_ISDIR=(0 0 0)
  _DLS_LINK=(0 0 0)
  _DLS_EXEC=(0 0 0)
  _DLS_SIZE=(0 0 0)
  _DLS_MTIME=(0 0 0)
  _DLS_KIND=(file file file)
  _DLS_SORT=natural
  _dls_apply_sort
  assert_eq "${(j: :)_DLS_NAMES}" "f1 f2 f10" "natural order compares digit runs"

  _DLS_NAMES=(a b m)
  _DLS_ISDIR=(0 0 1)
  _DLS_LINK=(0 0 0)
  _DLS_EXEC=(0 0 0)
  _DLS_SIZE=(0 0 0)
  _DLS_MTIME=(0 0 0)
  _DLS_KIND=(file file dir)
  _DLS_SORT=name
  _DLS_SORT_DIRS=first
  _dls_apply_sort
  assert_eq "${(j: :)_DLS_NAMES}" "m a b" "directories stay above files"
  _DLS_SORT_REVERSE=1
  _dls_apply_sort
  assert_eq "${(j: :)_DLS_NAMES}" "m b a" "reverse flips inside each group"
  assert_eq "$(_dls_sort_label)" "name~ dirs" "label marks reverse and dirs"

  _dls_list "$dir" 0
  _DLS_SORT=size
  _DLS_SORT_DIRS=mixed
  _DLS_SORT_REVERSE=0
  _dls_list "$dir" 0
  local si=-1 bi=-1 i
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    [[ ${_DLS_NAMES[i]} == small ]] && si=$i
    [[ ${_DLS_NAMES[i]} == big ]] && bi=$i
  done
  if (( si > 0 && bi > si )); then
    _dnav_test_pass "size order puts the shorter file first"
  else
    _dnav_test_fail "size order small=$si big=$bi"
  fi

  _DLS_SORT=mtime
  _dls_list "$dir" 0
  local oi=-1 ni=-1
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    [[ ${_DLS_NAMES[i]} == old ]] && oi=$i
    [[ ${_DLS_NAMES[i]} == new ]] && ni=$i
  done
  if (( oi > 0 && ni > oi )); then
    _dnav_test_pass "mtime order puts the older file first"
  else
    _dnav_test_fail "mtime order old=$oi new=$ni"
  fi
  _dls_config_defaults
}

test_dls_sort_dots() {
  local dir="$DLS_TMP/dots" rc="$DLS_TMP/dots-rc" joined warns i seen
  mkdir -p -- "$dir/.alpha" "$dir/.zeta" "$dir/alpha" "$dir/zeta"
  : > "$dir/.afile"
  : > "$dir/.zfile"
  : > "$dir/afile"
  : > "$dir/zfile"
  ln -s alpha "$dir/.ld"
  ln -s afile "$dir/.lf"

  _dls_config_defaults
  _DLS_SORT_DIRS=first
  _DLS_SORT_DOTS=first
  _dls_list "$dir" 1
  joined="${(j: :)_DLS_NAMES}"
  assert_eq "$joined" ".alpha .ld .zeta alpha zeta .afile .lf .zfile afile zfile" "dot dirs, dirs, dot files, files"
  assert_eq "$(_dls_sort_label)" "name dirs dots" "label marks both groups"

  _DLS_SORT_REVERSE=1
  _dls_list "$dir" 1
  joined="${(j: :)_DLS_NAMES}"
  assert_eq "$joined" ".zeta .ld .alpha zeta alpha .zfile .lf .afile zfile afile" "reverse stays inside each dot group"
  assert_eq "$(_dls_sort_label)" "name~ dirs dots" "label marks reverse, dirs, and dots"

  _DLS_SORT_REVERSE=0
  _DLS_SORT_DOTS=last
  _dls_list "$dir" 1
  joined="${(j: :)_DLS_NAMES}"
  assert_eq "$joined" "alpha zeta .alpha .ld .zeta afile zfile .afile .lf .zfile" "sort_dots last puts the dot group after its plain group"

  _DLS_SORT_DIRS=mixed
  _DLS_SORT_DOTS=first
  _dls_list "$dir" 1
  joined="${(j: :)_DLS_NAMES}"
  assert_eq "$joined" ".afile .alpha .ld .lf .zeta .zfile afile alpha zeta zfile" "dots first with mixed dirs keeps files and directories together"
  assert_eq "$(_dls_sort_label)" "name dots" "label omits dirs when that split is mixed"

  _DLS_SORT_DIRS=first
  _DLS_SORT_DOTS=mixed
  _dls_list "$dir" 1
  seen=0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if (( _DLS_ISDIR[i] )); then
      if (( seen )); then
        seen=2
        break
      fi
    else
      seen=1
    fi
  done
  if (( seen == 1 )); then
    _dnav_test_pass "mixed dots keeps every directory above every file"
  else
    _dnav_test_fail "mixed dots keeps every directory above every file"
  fi

  print -r -- "set sort_dirs first" > "$rc"
  print -r -- "set sort_dots first" >> "$rc"
  _dls_config_load "$rc"
  assert_eq "$_DLS_SORT_DIRS" "first" "rc sets sort_dirs"
  assert_eq "$_DLS_SORT_DOTS" "first" "rc sets sort_dots"
  print -r -- "set sort_dots nope" > "$rc"
  { _dls_config_load "$rc" } 2>/dev/null
  assert_eq "$_DLS_SORT_DOTS" "mixed" "a bad sort_dots value is ignored"
  warns="${(j: :)_DLS_RC_WARN}"
  assert_contains "$warns" "bad set" "bad sort_dots is reported"
  _dls_config_defaults
}

test_dls_kinds() {
  local dir="$DLS_TMP/kinds"
  mkdir -p -- "$dir/dir.png"
  printf x > "$dir/pic.png"
  printf x > "$dir/target"
  printf x > "$dir/run"
  chmod +x "$dir/run"
  ln -s target "$dir/linkname"
  _dls_config_defaults
  _DLS_EXT[png]=image
  _dls_list "$dir" 0
  assert_eq "$(_dls_kind_named pic.png)" "image" "png is image"
  assert_eq "$(_dls_kind_named linkname)" "link" "symlink is link"
  assert_eq "$(_dls_kind_named dir.png)" "dir" "directory wins over the suffix"
  assert_eq "$(_dls_kind_named run)" "exec" "executable file is exec"
  _dls_config_defaults
}

test_dls_styles_and_maps() {
  local rc="$DLS_TMP/rc-style"
  _dls_config_defaults
  print -r -- "highlight dir bold blue" > "$rc"
  _dls_config_load "$rc"
  assert_eq "${_DLS_STYLE[dir]}" "1;34" "bold blue is SGR 1;34"
  assert_eq "$(_dls_style dir 1)" $'\e[1;34;7m' "selection stacks reverse on the type"
  print -r -- "set colorscheme plain" > "$rc"
  _dls_config_load "$rc"
  assert_eq "${_DLS_STYLE[dir]:-}" "" "plain has no directory color"
  assert_eq "$(_dls_style file 0)" "" "plain file has no type color"
  assert_eq "$(_dls_style dir 1)" $'\e[7m' "plain selection is reverse"
  print -r -- "map q quit" > "$rc"
  print -r -- "map . quit" >> "$rc"
  _dls_config_load "$rc"
  assert_eq "$(_dls_action q)" "quit" "map q quits"
  assert_eq "$(_dls_action .)" "quit" "map replaces the dot key"
  assert_eq "$(_dls_action h)" "move-left" "unmapped keys keep the default"
  assert_eq "$(_dls_action ctrl-c)" "cancel" "ctrl-c stays cancel"
  assert_eq "${_DLS_MAP[ctrl-c]:-}" "" "ctrl-c is not a map entry"
  _dls_config_defaults
}

test_dls_rc_errors_and_source() {
  local dir="$DLS_TMP/rcs" warns
  mkdir -p -- "$dir"
  print -r -- "set sort nope" > "$dir/bad"
  print -r -- "set sort ext" >> "$dir/bad"
  { _dls_config_load "$dir/bad" } 2>/dev/null
  assert_eq "$_DLS_SORT" "ext" "a bad line does not stop the next"
  warns="${(j: :)_DLS_RC_WARN}"
  assert_contains "$warns" "bad set" "bad line is reported"
  assert_contains "$warns" "dls: rc:" "warning uses the rc prefix"

  print -r -- "set sort mtime" > "$dir/extra"
  print -r -- "source extra" > "$dir/main"
  _dls_config_load "$dir/main"
  assert_eq "$_DLS_SORT" "mtime" "source loads the other file"

  print -r -- "source b" > "$dir/a"
  print -r -- "source a" > "$dir/b"
  print -r -- "set sort size" >> "$dir/b"
  { _dls_config_load "$dir/a" } 2>/dev/null
  assert_eq "$_DLS_SORT" "size" "cycle does not drop the rest of the file"
  warns="${(j: :)_DLS_RC_WARN}"
  assert_contains "$warns" "cycle" "source cycle warns"
  if [[ $warns == *cycle*cycle* ]]; then
    _dnav_test_fail "source cycle warned more than once"
  else
    _dnav_test_pass "source cycle warns once"
  fi
  _dls_config_defaults
}

run_test test_dls_source_is_standalone
run_test test_dls_layout_and_move
run_test test_dls_scroll_follows_move
run_test test_dls_place_fits_the_screen
run_test test_dls_cell_stays_within_width
run_test test_dls_cached_line_matches_cell
run_test test_dls_list_sort_and_hidden
run_test test_dls_enter_and_parent
run_test test_dls_unreadable_keeps_listing
run_test test_dls_fit_keeps_slash_inside_width
run_test test_dls_stub_defines_dls_without_loading
run_test test_dls_missing_rc_keeps_defaults
run_test test_dls_sort_orders
run_test test_dls_sort_dots
run_test test_dls_kinds
run_test test_dls_styles_and_maps
run_test test_dls_rc_errors_and_source

test_dls_ls_flags() {
  local dir="$DLS_TMP/flags" rc joined i si bi
  mkdir -p -- "$dir/sub/child" "$dir/.hid" "$dir/a" "$dir/m"
  : > "$dir/visible"
  : > "$dir/.secret"
  : > "$dir/keep"
  : > "$dir/drop~"
  : > "$dir/drop.o"
  : > "$dir/b"
  : > "$dir/c"
  printf 'x' > "$dir/small"
  printf 'xxxxxx' > "$dir/big"
  touch -d '2020-01-01 00:00:00' "$dir/small" || touch -t 202001010000 "$dir/small"
  touch -d '2024-06-01 00:00:00' "$dir/big" || touch -t 202406010000 "$dir/big"
  printf x > "$dir/run"
  chmod +x "$dir/run"
  ln -s small "$dir/link"
  ln -s a "$dir/linkdir"

  _dls_parse_args -lah
  assert_eq "$?" "0" "-lah parses"
  assert_eq "$_DLS_HELP" "0" "-h is human-readable, not help"
  assert_eq "$_DLS_CLI_DOTS" "a" "-a is --all"
  assert_eq "$_DLS_CLI_LONG" "1" "-l is a long listing"
  assert_eq "$_DLS_CLI_HUMAN" "1" "-h is human sizes"
  _dls_parse_args --help
  assert_eq "$_DLS_HELP" "1" "--help is help"
  { _dls_parse_args -Q } 2>/dev/null
  assert_eq "$?" "2" "an unknown option returns 2"

  assert_eq "$(_dls_human 1024 1024)" "1.0K" "1024 bytes is 1.0K"
  assert_eq "$(_dls_human 1536 1024)" "1.5K" "1536 bytes is 1.5K"
  assert_eq "$(_dls_human 10240 1000)" "11k" "10240 bytes is 11k in SI"
  assert_eq "$(_dls_mode_str 33188)" "-rw-r--r--" "0644 is -rw-r--r--"

  _dls_config_defaults
  _dls_parse_args -A
  _dls_apply_cli
  _dls_list "$dir" "$_DLS_SHOW_HIDDEN"
  joined="${(j: :)_DLS_NAMES}"
  assert_contains "$joined" ".hid" "-A shows a dot directory"
  assert_contains "$joined" ".secret" "-A shows a dot file"
  if [[ $joined == *' . '* || $joined == '. '* || $joined == *' ..'* ]]; then
    _dnav_test_fail "-A hides . and .."
  else
    _dnav_test_pass "-A hides . and .."
  fi

  _dls_parse_args -a
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" "$_DLS_SHOW_HIDDEN"
  local has_dot=0 has_dotdot=0 name
  for name in "${_DLS_NAMES[@]}"; do
    [[ $name == . ]] && has_dot=1
    [[ $name == .. ]] && has_dotdot=1
  done
  if (( has_dot && has_dotdot )); then
    _dnav_test_pass "-a lists . and .."
  else
    _dnav_test_fail "-a lists . and .."
  fi

  _dls_parse_args -B
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  joined="${(j: :)_DLS_NAMES}"
  assert_contains "$joined" "keep" "-B keeps an ordinary name"
  if [[ $joined == *'drop~'* ]]; then
    _dnav_test_fail "-B hides backup names"
  else
    _dnav_test_pass "-B hides backup names"
  fi

  _dls_parse_args -I '*.o'
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  joined="${(j: :)_DLS_NAMES}"
  if [[ $joined == *'drop.o'* ]]; then
    _dnav_test_fail "-I hides the shell pattern"
  else
    _dnav_test_pass "-I hides the shell pattern"
  fi
  assert_contains "$joined" "keep" "-I leaves other names"

  _dls_parse_args --hide keep
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  joined="${(j: :)_DLS_NAMES}"
  if [[ $joined == *'keep'* ]]; then
    _dnav_test_fail "--hide drops the pattern"
  else
    _dnav_test_pass "--hide drops the pattern"
  fi
  _dls_parse_args --hide keep -a
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" "$_DLS_SHOW_HIDDEN"
  assert_contains "${(j: :)_DLS_NAMES}" "keep" "-a shows a --hide pattern"

  _dls_parse_args -t
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  si=0; bi=0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    [[ ${_DLS_NAMES[i]} == small ]] && si=$i
    [[ ${_DLS_NAMES[i]} == big ]] && bi=$i
  done
  if (( bi > 0 && si > bi )); then
    _dnav_test_pass "-t puts the newer file first"
  else
    _dnav_test_fail "-t puts the newer file first (big=$bi small=$si)"
  fi
  _dls_parse_args -tr
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  si=0; bi=0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    [[ ${_DLS_NAMES[i]} == small ]] && si=$i
    [[ ${_DLS_NAMES[i]} == big ]] && bi=$i
  done
  if (( si > 0 && bi > si )); then
    _dnav_test_pass "-tr puts the older file first"
  else
    _dnav_test_fail "-tr puts the older file first (small=$si big=$bi)"
  fi
  _dls_parse_args -S
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  si=0; bi=0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    [[ ${_DLS_NAMES[i]} == small ]] && si=$i
    [[ ${_DLS_NAMES[i]} == big ]] && bi=$i
  done
  if (( bi > 0 && si > bi )); then
    _dnav_test_pass "-S puts the larger file first"
  else
    _dnav_test_fail "-S puts the larger file first (big=$bi small=$si)"
  fi

  _dls_parse_args --group-directories-first -r
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  local seen_file=0 bad=0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if (( _DLS_ISDIR[i] )); then
      (( seen_file )) && bad=1
    else
      seen_file=1
    fi
  done
  if (( bad == 0 && seen_file )); then
    _dnav_test_pass "--group-directories-first keeps directories above files"
  else
    _dnav_test_fail "--group-directories-first keeps directories above files"
  fi
  assert_eq "$(_dls_sort_label)" "name~ dirs" "-r marks the label reversed"

  local pair="$DLS_TMP/pair"
  mkdir -p -- "$pair"
  : > "$pair/a"
  : > "$pair/b"
  touch -d '2020-01-01 00:00:00' "$pair/a" || touch -t 202001010000 "$pair/a"
  touch -d '2024-06-01 00:00:00' "$pair/b" || touch -t 202406010000 "$pair/b"
  _dls_parse_args -l -c
  _dls_config_defaults
  _dls_apply_cli
  assert_eq "$_DLS_TIME" "ctime" "-c selects ctime"
  assert_eq "$_DLS_SORT" "name" "-l -c still sorts by name"
  assert_eq "$_DLS_LONG" "1" "-l -c is a long listing"
  _dls_list "$pair" 0
  assert_eq "${(j: :)_DLS_NAMES}" "a b" "-l -c keeps name order"
  _dls_parse_args -c
  _dls_config_defaults
  _dls_apply_cli
  assert_eq "$_DLS_SORT" "time" "-c alone sorts by time"
  assert_eq "$_DLS_SORT_REVERSE" "1" "-c alone is newest first"

  _dls_parse_args -F
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    case ${_DLS_NAMES[i]} in
      run) assert_eq "$(_dls_suffix "$i")" "*" "-F marks an executable with *" ;;
      link) assert_eq "$(_dls_suffix "$i")" "@" "-F marks a symlink with @" ;;
      linkdir) assert_eq "$(_dls_suffix "$i")" "@" "-F marks a symlink to a directory with @" ;;
    esac
  done
  _dls_parse_args --indicator-style=none
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if [[ ${_DLS_NAMES[i]} == a ]]; then
      assert_eq "$(_dls_suffix "$i")" "" "--indicator-style=none drops the slash"
    fi
  done

  # 1536 bytes
  python3 -c 'open("'"$dir"'/wide","wb").write(b"x"*1536)'
  _dls_parse_args -l -h
  _dls_config_defaults
  _dls_apply_cli
  _dls_list "$dir" 0
  for (( i = 1; i <= $#_DLS_NAMES; i++ )); do
    if [[ ${_DLS_NAMES[i]} == wide ]]; then
      assert_contains "$(_dls_row_plain "$i")" "-rw-r--r--" "long row shows the mode"
      assert_contains "$(_dls_row_plain "$i")" "1.5K" "long row uses human sizes"
    elif [[ ${_DLS_NAMES[i]} == link ]]; then
      assert_contains "$(_dls_row_plain "$i")" "link -> small" "long row shows the symlink target"
    fi
  done

  _dls_parse_args -d
  _dls_config_defaults
  _dls_apply_cli
  _dls_list_operands "$dir/sub"
  assert_eq "${(j: :)_DLS_NAMES}" "$dir/sub" "-d lists the directory, not its children"
  if [[ ${(j: :)_DLS_NAMES} == *child* ]]; then
    _dnav_test_fail "-d does not list children"
  else
    _dnav_test_pass "-d does not list children"
  fi

  _dls_parse_args
  _dls_config_defaults
  _dls_apply_cli
  _dls_list_operands "$dir/keep" "$dir/visible"
  assert_eq "${(j: :)_DLS_NAMES}" "$dir/keep $dir/visible" "two file operands are the whole listing"

  rc="$DLS_TMP/flags-rc"
  print -r -- "set sort name" > "$rc"
  print -r -- "set sort_reverse false" >> "$rc"
  print -r -- "highlight dir bold blue" >> "$rc"
  _dls_parse_args -t
  _dls_config_load "$rc"
  _dls_apply_cli
  assert_eq "$_DLS_SORT" "time" "a sort flag replaces the rc sort"
  assert_eq "$_DLS_SORT_REVERSE" "1" "a sort flag uses the ls direction, not the rc"
  _dls_parse_args --color=never
  _dls_config_load "$rc"
  _dls_apply_cli
  assert_eq "${_DLS_STYLE[dir]:-}" "" "--color=never drops type color"

  _dls_cli_reset
  _dls_config_defaults
}

test_dls_filter() {
  local rc="$DLS_TMP/rc-filter" dir="$DLS_TMP/filter" sig text
  local open_rc=0 reload_rc=0
  _dls_config_defaults
  _DLS_FILTER=""
  _DLS_FILTERING=0

  assert_eq "$(_dls_action /)" "filter" "/ starts a filter"
  assert_ok _dls_filter_ok bashrc bash
  assert_ok _dls_filter_ok bashrc BASH
  assert_ok _dls_filter_ok bash_history "bash his"
  assert_ok _dls_filter_ok his_bash "bash his"
  assert_fail _dls_filter_ok bashrc "bash his"
  assert_fail _dls_filter_ok other bash
  assert_ok _dls_filter_ok bashrc "bash -his"
  assert_fail _dls_filter_ok bash_history "bash -his"
  assert_ok _dls_filter_ok foo-bar foo-bar
  assert_fail _dls_filter_ok foo-bar "foo -bar"
  assert_ok _dls_filter_ok foo-baz "foo -bar"
  assert_ok _dls_filter_ok '-bashrc' '-bash'
  assert_fail _dls_filter_ok bashrc '-bash'
  assert_ok _dls_filter_ok bashrc ""
  assert_ok _dls_filter_ok bashrc "   "
  assert_ok _dls_filter_ok bashrc "bash -"
  assert_ok _dls_filter_ok other " -"
  assert_ok _dls_filter_ok bash_history "bash  his"
  assert_fail _dls_filter_ok bashrc "bash  his"
  assert_fail _dls_filter_ok bashrc '-'
  assert_ok _dls_filter_ok '-bashrc' '-'
  assert_fail _dls_filter_ok bash_history " -his"
  assert_ok _dls_filter_ok bashrc " -his"
  assert_fail _dls_filter_ok ab 'a*b'
  assert_ok _dls_filter_ok 'a*b' 'a*b'
  assert_ok _dls_filter_ok 'a[b' 'a[b'

  _DLS_NAMES=(aaa bashrc bash_history foo-bar '-bashrc')
  _DLS_VIS=()
  _DLS_SEL=0
  _DLS_FILTER=""
  _dls_show_sync
  assert_eq "${(j: :)_DLS_VIS}" "1 2 3 4 5" "an empty filter lists every name"
  _DLS_SEL=2
  _DLS_FILTER=bash
  _DLS_SCROLL=4
  _dls_show_sync
  assert_eq "${(j: :)_DLS_VIS}" "2 3 5" "bash keeps every name that contains it"
  assert_eq "$_DLS_SEL" "1" "the highlighted name stays put"
  assert_eq "${_DLS_NAMES[_DLS_VIS[_DLS_SEL+1]]}" "bash_history" "selection is still bash_history"
  assert_eq "$_DLS_SCROLL" "4" "a view rebuild keeps the scroll offset"
  _DLS_FILTER="bash his"
  _dls_show_sync
  assert_eq "${(j: :)_DLS_VIS}" "3" "both words are required"
  assert_eq "${_DLS_NAMES[_DLS_VIS[_DLS_SEL+1]]}" "bash_history" "bash his stays on bash_history"
  _DLS_FILTER="bash -his"
  _dls_show_sync
  assert_eq "${(j: :)_DLS_VIS}" "2 5" "a spaced dash hides names with the next word"
  assert_eq "${_DLS_NAMES[_DLS_VIS[_DLS_SEL+1]]}" "bashrc" "a hidden selection lands on the first remaining name"

  _DLS_FILTER=""
  _DLS_FILTERING=1
  _dls_show_sync
  _dls_filter_key b
  _dls_filter_key a
  _dls_filter_key s
  _dls_filter_key h
  assert_eq "$_DLS_FILTER" "bash" "typed characters build the query"
  assert_eq "$_DLS_FILTERING" "1" "typing stays in the filter"
  assert_eq "$_DLS_SCROLL" "0" "typing starts the view at the top"
  _dls_filter_key enter
  assert_eq "$_DLS_FILTERING" "0" "enter commits the filter"
  assert_eq "$_DLS_FILTER" "bash" "enter keeps the query"
  assert_eq "${(j: :)_DLS_VIS}" "2 3 5" "the committed filter still hides"

  _DLS_FILTERING=1
  _dls_filter_key backspace
  assert_eq "$_DLS_FILTER" "bas" "backspace deletes one character"
  _DLS_FILTER=""
  _dls_show_sync
  _dls_filter_key backspace
  assert_eq "$_DLS_FILTERING" "0" "backspace on an empty query leaves the filter"

  _DLS_FILTERING=1
  _DLS_FILTER=nope
  _dls_show_sync
  _dls_filter_key esc
  assert_eq "$_DLS_FILTER" "" "escape clears the query"
  assert_eq "$_DLS_FILTERING" "0" "escape leaves the filter"
  assert_eq "${(j: :)_DLS_VIS}" "1 2 3 4 5" "escape shows every name"

  _DLS_FILTERING=1
  _DLS_FILTER=ab
  _dls_filter_key left
  assert_eq "$_DLS_FILTER" "ab" "arrows do not change the query"
  assert_eq "$_DLS_FILTERING" "1" "arrows stay in the filter"
  _DLS_FILTERING=0
  _DLS_FILTER=kept
  if _dls_filter_key x; then
    _dnav_test_fail "a closed filter accepted a key"
  else
    _dnav_test_pass "a closed filter ignores filter keys"
  fi
  assert_eq "$_DLS_FILTER" "kept" "a closed filter does not change the query"

  _DLS_FILTERING=1
  _DLS_FILTER=""
  _dls_show_sync
  _dls_filter_key b
  _dls_filter_key a
  _dls_filter_key s
  _dls_filter_key h
  _dls_filter_key " "
  _dls_filter_key -
  _dls_filter_key h
  _dls_filter_key i
  _dls_filter_key s
  assert_eq "$_DLS_FILTER" "bash -his" "a typed dash is part of the query"
  assert_eq "${(j: :)_DLS_VIS}" "2 5" "typed words hide the same names"
  _dls_filter_key enter

  print -r -- "map / quit" > "$rc"
  _dls_config_load "$rc"
  assert_eq "$(_dls_action /)" "quit" "a map can take /"
  print -r -- "map f filter" > "$rc"
  _dls_config_load "$rc"
  assert_eq "$(_dls_action f)" "filter" "filter can be bound to another key"
  assert_eq "$(_dls_action /)" "filter" "the default / binding remains"

  mkdir -p -- "$dir"
  : > "$dir/bashrc"
  : > "$dir/other"
  _dls_config_defaults
  _DLS_FILTER=""
  _DLS_FILTERING=0
  _DLS_COLS=80
  _dls_list "$dir" 0
  _dls_prepare
  sig="$_DLS_SIG"
  _DLS_FILTER=bash
  _dls_show_sync
  _dls_prepare
  assert_eq "$_DLS_SIG" "$sig" "a filter does not rebuild the cell cache"
  assert_eq "${(j: :)_DLS_NAMES}" "bashrc other" "the full listing stays in place"
  assert_eq "${_DLS_NAMES[_DLS_VIS[1]]}" "bashrc" "the view hides other"
  assert_eq "$#_DLS_VIS" "1" "bash leaves one visible name"

  _DLS_FILTERING=1
  text="$(_dls_status_text / "" 40)"
  assert_contains "$text" "/bash_" "the status shows the query and a cursor"
  if [[ $text == *hjkl* ]]; then
    _dnav_test_fail "filter status still shows the movement hint"
  else
    _dnav_test_pass "filter status replaces the movement hint"
  fi
  _DLS_FILTERING=0
  text="$(_dls_status_text / "" 40)"
  assert_contains "$text" "/bash" "a committed filter stays on the status line"
  if [[ $text == *bash_* ]]; then
    _dnav_test_fail "a committed filter still shows the cursor"
  else
    _dnav_test_pass "a committed filter has no cursor"
  fi

  (
    _DLS_FILTER=bash
    _DLS_FILTERING=1
    _dls_open "$dir" || exit 1
    [[ -z $_DLS_FILTER ]] || exit 2
    (( _DLS_FILTERING == 0 )) || exit 3
    [[ ${(j: :)_DLS_NAMES} == *other* ]] || exit 4
    exit 0
  ) || open_rc=$?
  if (( open_rc )); then
    _dnav_test_fail "opening a directory clears the filter (rc=$open_rc)"
  else
    _dnav_test_pass "opening a directory clears the filter"
  fi

  (
    cd -- "$dir" || exit 1
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _dls_list "$PWD" 0 || exit 2
    _DLS_FILTER=bash
    _DLS_CWD="$PWD"
    _dls_show_sync
    _dls_reload || exit 3
    [[ $_DLS_FILTER == bash ]] || exit 4
    (( $#_DLS_VIS == 1 )) || exit 5
    [[ ${_DLS_NAMES[_DLS_VIS[1]]} == bashrc ]] || exit 6
    exit 0
  ) || reload_rc=$?
  if (( reload_rc )); then
    _dnav_test_fail "reload keeps the filter (rc=$reload_rc)"
  else
    _dnav_test_pass "reload keeps the filter"
  fi

  _DLS_FILTER=""
  _DLS_FILTERING=0
  _dls_config_defaults
}

test_dls_shift_enter() {
  local rc="$DLS_TMP/rc-shift" dir="$DLS_TMP/shift" tok quit_rc=0 open_rc=0 file_rc=0 jump_rc=0
  _dls_config_defaults
  assert_eq "$(_dls_action enter)" "open" "enter still opens"
  assert_eq "$(_dls_action shift-enter)" "quit-dir" "shift-enter jumps out of dls"

  for tok in A B C D '3~' '13;2u' '13;2;1u' '13;2:1u' '13:10;2u' '13:10;2:1u' '13;130u' '13;66u' '13;194u' '10;130u' '27;2;13~' '27;2;13;1~' '27;130;13~' '27u' '27;2u' '27;2:1u' '27;129u' '27;2;27~' '99;5u' '99;5:1u' '99;133u' '27;5;99~' '27;133;99~' '13;5u' '99~' '1;2D' '1;130D'; do
    _dls_match_csi "$tok"
    case $tok in
      A) assert_eq "$REPLY" "up" "dls csi up" ;;
      B) assert_eq "$REPLY" "down" "dls csi down" ;;
      C) assert_eq "$REPLY" "right" "dls csi right" ;;
      D) assert_eq "$REPLY" "left" "dls csi left" ;;
      3~) assert_eq "$REPLY" "delete" "dls csi delete" ;;
      13\;2u|13\;2\;1u|13\;2:1u|13:10\;2u|13:10\;2:1u|13\;130u|13\;66u|13\;194u|10\;130u|27\;2\;13~|27\;2\;13\;1~|27\;130\;13~) assert_eq "$REPLY" "shift-enter" "dls csi $tok" ;;
      27u|27\;2u|27\;2:1u|27\;129u|27\;2\;27~) assert_eq "$REPLY" "esc" "dls csi $tok is escape" ;;
      99\;5u|99\;5:1u|99\;133u|27\;5\;99~|27\;133\;99~) assert_eq "$REPLY" "ctrl-c" "dls csi $tok is ctrl-c" ;;
      13\;5u|99~) assert_eq "$REPLY" "ignore" "dls csi $tok is not shift-enter" ;;
      1\;2D|1\;130D) assert_eq "$REPLY" "left" "dls shift-left stays left" ;;
      *) _dnav_test_fail "untested dls csi $tok" ;;
    esac
  done

  assert_fail _dls_config_map '<s-enter> explode'
  assert_eq "$(_dls_action shift-enter)" "quit-dir" "a bad action leaves shift-enter on quit-dir"
  assert_ok _dls_config_map '<s-enter> quit-dir'
  assert_eq "$(_dls_action shift-enter)" "quit-dir" "map <s-enter> quit-dir"
  assert_ok _dls_config_map '<Shift-Enter> open'
  assert_eq "$(_dls_action shift-enter)" "open" "map <Shift-Enter> open"
  print -r -- "map <shift-enter> quit-dir" > "$rc"
  _dls_config_load "$rc"
  assert_eq "$(_dls_action shift-enter)" "quit-dir" "rc map <shift-enter> quit-dir"
  assert_eq "$(_dls_action enter)" "open" "enter stays open when shift-enter is remapped"

  _DLS_FILTERING=1
  _DLS_FILTER=ab
  _dls_filter_key shift-enter
  assert_eq "$_DLS_FILTER" "ab" "shift-enter does not join the query"
  assert_eq "$_DLS_FILTERING" "1" "shift-enter stays in the filter"
  _DLS_FILTER=""
  _DLS_FILTERING=0

  mkdir -p -- "$dir/sub"
  : > "$dir/file"
  : > "$dir/sub/inside"
  (
    local i sel=-1
    _dls_config_defaults
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _dls_list "$dir" 0 || exit 1
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == sub ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 2
    _DLS_SEL=$sel
    _DLS_DONE=0
    dls() { exit 9; }
    _dls_quit_dir || exit 3
    [[ $PWD == "$dir/sub" ]] || exit 4
    (( _DLS_DONE == 1 )) || exit 5
    (( _DLS_RC == 0 )) || exit 6
    [[ ${(j: :)_DLS_NAMES} == *file* ]] || exit 7
    [[ ${(j: :)_DLS_NAMES} != *inside* ]] || exit 8
    exit 0
  ) || quit_rc=$?
  if (( quit_rc )); then
    _dnav_test_fail "quit-dir cds without listing again (rc=$quit_rc)"
  else
    _dnav_test_pass "quit-dir cds without listing again"
  fi

  (
    local i sel=-1
    _dls_config_defaults
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _dls_list "$dir" 0 || exit 1
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == file ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 2
    _DLS_SEL=$sel
    _DLS_DONE=0
    if _dls_quit_dir; then
      exit 3
    fi
    (( _DLS_DONE == 0 )) || exit 4
    [[ $PWD != "$dir/sub" ]] || exit 5
    exit 0
  ) || file_rc=$?
  if (( file_rc )); then
    _dnav_test_fail "quit-dir on a file stays put (rc=$file_rc)"
  else
    _dnav_test_pass "quit-dir on a file stays put"
  fi

  (
    local i sel=-1
    _dls_config_defaults
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _dls_list "$dir" 0 || exit 1
    _DLS_FILTER=keep
    _DLS_FILTERING=0
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == sub ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 2
    _DLS_SEL=$sel
    _DLS_DONE=0
    dls() { exit 9; }
    _dls_draw() { : }
    _dls_handle_key shift-enter
    (( _DLS_DONE == 1 )) || exit 3
    (( _DLS_RC == 0 )) || exit 4
    [[ $PWD == "$dir/sub" ]] || exit 5
    [[ ${(j: :)_DLS_NAMES} == *file* ]] || exit 6
    [[ ${(j: :)_DLS_NAMES} != *inside* ]] || exit 7
    [[ -z $_DLS_FILTER ]] || exit 8
    (( _DLS_FILTERING == 0 )) || exit 9
    exit 0
  ) || jump_rc=$?
  if (( jump_rc )); then
    _dnav_test_fail "shift-enter cds and leaves (rc=$jump_rc)"
  else
    _dnav_test_pass "shift-enter cds and leaves"
  fi

  (
    local i sel=-1
    _dls_config_defaults
    _dls_config_map '<s-enter> open' || exit 1
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _dls_list "$dir" 0 || exit 2
    _DLS_FILTER=keep
    _DLS_FILTERING=0
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == sub ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 3
    _DLS_SEL=$sel
    _DLS_DONE=1
    dls() { exit 9; }
    _dls_draw() { : }
    _dls_handle_key shift-enter
    (( _DLS_DONE == 0 )) || exit 4
    [[ $PWD == "$dir/sub" ]] || exit 5
    [[ ${(j: :)_DLS_NAMES} == *inside* ]] || exit 6
    [[ -z $_DLS_FILTER ]] || exit 7
    (( _DLS_FILTERING == 0 )) || exit 8
    exit 0
  ) || open_rc=$?
  if (( open_rc )); then
    _dnav_test_fail "map open stays inside dls (rc=$open_rc)"
  else
    _dnav_test_pass "map open stays inside dls"
  fi

  _DLS_FILTER=""
  _DLS_FILTERING=0
  _DLS_DONE=0
  _dls_config_defaults
}

# $7 is 1 when the expression should clear for this leave.
_dls_cls_expect() {
  local expr="$1" key="$2" action="$3" drawn="$4" rows="$5" want="$6" msg="$7"
  local got=0
  _DLS_AUTO_CLS="$expr"
  _dls_auto_cls_hit "$key" "$action" "$drawn" "$rows" && got=1
  assert_eq "$got" "$want" "$msg"
}

test_dls_auto_cls() {
  local rc="$DLS_TMP/rc-cls" dir="$DLS_TMP/cls" warns here jump_rc=0 file_rc=0 open_rc=0
  local log_once
  _dls_config_defaults
  assert_eq "$_DLS_AUTO_CLS" "off" "auto clear starts off"

  assert_ok _dls_auto_cls_set always
  assert_eq "$_DLS_AUTO_CLS" "always" "always stores always"
  assert_ok _dls_auto_cls_set 'shift-enter | 50%'
  assert_eq "$_DLS_AUTO_CLS" "shift-enter|50%" "spaces collapse around | "
  assert_ok _dls_auto_cls_set 'S-ENTER'
  assert_eq "$_DLS_AUTO_CLS" "s-enter" "s-enter stays literal"
  assert_ok _dls_auto_cls_set 'off | always'
  assert_eq "$_DLS_AUTO_CLS" "off|always" "aliases stay lowercase"
  assert_fail _dls_auto_cls_set '101%'
  assert_eq "$_DLS_AUTO_CLS" "off|always" "101% keeps the previous expression"
  assert_fail _dls_auto_cls_set 'shift-enter|'
  assert_fail _dls_auto_cls_set '|50%'
  assert_fail _dls_auto_cls_set 'shift-enter&'
  assert_fail _dls_auto_cls_set 'pct>=101'
  assert_fail _dls_auto_cls_set 'pct>='
  assert_fail _dls_auto_cls_set 'rows>='
  assert_fail _dls_auto_cls_set nope
  assert_eq "$_DLS_AUTO_CLS" "off|always" "an unknown word keeps the previous expression"

  print -r -- "set auto_cls shift-enter" > "$rc"
  print -r -- "set auto_cls nope" >> "$rc"
  { _dls_config_load "$rc" } 2>/dev/null
  assert_eq "$_DLS_AUTO_CLS" "shift-enter" "a bad rc line keeps the earlier auto_cls"
  warns="${(j: :)_DLS_RC_WARN}"
  assert_contains "$warns" "bad set" "a bad auto_cls is reported"
  print -r -- "set auto_cls shift-enter | 50%" > "$rc"
  _dls_config_load "$rc"
  assert_eq "$_DLS_AUTO_CLS" "shift-enter|50%" "rc spaces collapse to shift-enter|50%"
  print -r -- "set sort ext" > "$rc"
  print -r -- "set sort name extra" >> "$rc"
  { _dls_config_load "$rc" } 2>/dev/null
  assert_eq "$_DLS_SORT" "ext" "other set lines still take one value"

  _dls_cls_expect off esc quit 20 20 0 "off never clears"
  _dls_cls_expect never ctrl-c cancel 20 20 0 "never never clears"
  _dls_cls_expect always ctrl-c cancel 4 20 1 "always clears a cancel"
  _dls_cls_expect always "" cancel 4 20 1 "always clears a read failure"
  _dls_cls_expect 'on' esc quit 1 20 1 "on clears any leave"
  _dls_cls_expect shift-enter shift-enter quit-dir 1 20 1 "shift-enter clears that key"
  _dls_cls_expect shift-enter enter open 20 20 0 "shift-enter ignores enter"
  _dls_cls_expect shift-enter esc quit 20 20 0 "shift-enter ignores escape"
  _dls_cls_expect s-enter shift-enter quit-dir 1 40 1 "s-enter matches shift-enter"
  _dls_cls_expect enter enter quit 1 20 1 "enter clears when that key leaves"
  _dls_cls_expect enter shift-enter quit-dir 20 20 0 "enter ignores shift-enter"
  _dls_cls_expect '50%' esc quit 1 2 1 "one row of two is 50%"
  _dls_cls_expect '51%' esc quit 1 2 0 "51% misses one row of two"
  _dls_cls_expect '50%' esc quit 1 0 0 "a missing screen makes percent false"
  _dls_cls_expect '0%' esc quit 1 0 0 "zero percent is still false without a screen"
  _dls_cls_expect 'pct>=50' esc quit 1 2 1 "pct>=50 matches one row of two"
  _dls_cls_expect 'pct>50' esc quit 1 2 0 "pct>50 misses one row of two"
  _dls_cls_expect 'pct==50' esc quit 1 2 1 "pct==50 matches one row of two"
  _dls_cls_expect 'pct<=50' esc quit 1 2 1 "pct<=50 matches one row of two"
  _dls_cls_expect 'pct<50' esc quit 1 2 0 "pct<50 misses one row of two"
  _dls_cls_expect 'pct=50' esc quit 1 2 1 "pct=50 matches one row of two"
  _dls_cls_expect 'shift-enter|50%' enter open 1 2 1 "or clears on the percent"
  _dls_cls_expect 'shift-enter|50%' shift-enter quit-dir 1 100 1 "or clears on the key"
  _dls_cls_expect 'shift-enter|50%' enter open 1 100 0 "or misses when both sides miss"
  _dls_cls_expect 'shift-enter&50%' shift-enter quit-dir 1 2 1 "and clears when both match"
  _dls_cls_expect 'shift-enter&50%' shift-enter quit-dir 1 100 0 "and misses a short grid"
  _dls_cls_expect 'shift-enter&50%' enter open 20 20 0 "and misses the other key"
  _dls_cls_expect 'rows>10' esc quit 11 40 1 "rows>10 counts painted lines"
  _dls_cls_expect 'rows>10' esc quit 10 40 0 "rows>10 misses ten lines"
  _dls_cls_expect 'rows>=12' esc quit 12 80 1 "rows>=12 matches twelve lines"
  _dls_cls_expect 'rows=4' esc quit 4 80 1 "rows=4 matches four lines"
  _dls_cls_expect 'rows==4' esc quit 5 80 0 "rows==4 misses five lines"
  _dls_cls_expect quit esc quit 1 20 1 "quit matches the action"
  _dls_cls_expect quit q quit 1 20 1 "quit matches a remapped key"
  _dls_cls_expect quit esc "" 1 20 0 "quit does not match the key alone"
  _dls_cls_expect esc esc quit 1 20 1 "esc matches the key"
  _dls_cls_expect esc q quit 1 20 0 "esc does not match another quit key"
  _dls_cls_expect ctrl-c ctrl-c cancel 1 20 1 "ctrl-c matches that key"
  _dls_cls_expect ctrl-c "" cancel 1 20 0 "ctrl-c does not match a bare cancel"
  _dls_cls_expect cancel "" cancel 1 20 1 "cancel matches a read failure"
  _dls_cls_expect cancel ctrl-c cancel 1 20 1 "cancel matches ctrl-c"
  _dls_cls_expect 'off|always' esc quit 1 20 1 "or with off still clears"
  _dls_cls_expect 'off&always' esc quit 20 20 0 "and with off never clears"
  _dls_cls_expect 'enter&50%|rows>10' enter quit 1 2 1 "a mixed clause can match the first side"
  _dls_cls_expect 'enter&50%|rows>10' esc quit 11 100 1 "a mixed clause can match the row side"
  _dls_cls_expect 'enter&50%|rows>10' esc quit 10 100 0 "a mixed clause misses when both sides miss"

  _DLS_DONE=0
  _DLS_EXIT_KEY=""
  _DLS_EXIT_ACTION=""
  _DLS_DRAW_ROW=0
  _dls_handle_key esc
  assert_eq "$_DLS_EXIT_KEY" "esc" "escape records the key"
  assert_eq "$_DLS_EXIT_ACTION" "quit" "escape records quit"
  assert_eq "$_DLS_DONE" "1" "escape leaves"
  assert_eq "$_DLS_RC" "0" "escape succeeds"

  here="$PWD"
  _DLS_ORIGIN="$PWD"
  _DLS_DRAW_ROW=0
  _DLS_EXIT_KEY=""
  _DLS_EXIT_ACTION=""
  _dls_handle_key ctrl-c
  assert_eq "$_DLS_EXIT_KEY" "ctrl-c" "ctrl-c records the key"
  assert_eq "$_DLS_EXIT_ACTION" "cancel" "ctrl-c records cancel"
  assert_eq "$_DLS_DONE" "1" "ctrl-c leaves"
  assert_eq "$_DLS_RC" "130" "ctrl-c returns 130"
  assert_eq "$PWD" "$here" "ctrl-c stays when origin is here"

  mkdir -p -- "$dir/sub"
  : > "$dir/file"
  : > "$dir/sub/inside"
  (
    local i sel=-1
    _dls_config_defaults
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _DLS_EXIT_KEY=""
    _DLS_EXIT_ACTION=""
    _dls_list "$dir" 0 || exit 1
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == sub ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 2
    _DLS_SEL=$sel
    _DLS_DONE=0
    dls() { exit 9; }
    _dls_draw() { : }
    _dls_handle_key shift-enter
    [[ $_DLS_EXIT_KEY == shift-enter ]] || exit 3
    [[ $_DLS_EXIT_ACTION == quit-dir ]] || exit 4
    (( _DLS_DONE == 1 )) || exit 5
    [[ $PWD == "$dir/sub" ]] || exit 6
    exit 0
  ) || jump_rc=$?
  if (( jump_rc )); then
    _dnav_test_fail "shift-enter records quit-dir (rc=$jump_rc)"
  else
    _dnav_test_pass "shift-enter records quit-dir"
  fi

  (
    local i sel=-1
    _dls_config_defaults
    _DLS_CWD="$dir"
    _DLS_FILTER=""
    _DLS_FILTERING=0
    _DLS_EXIT_KEY=""
    _DLS_EXIT_ACTION=""
    _dls_list "$dir" 0 || exit 1
    for (( i = 1; i <= $#_DLS_VIS; i++ )); do
      [[ ${_DLS_NAMES[_DLS_VIS[i]]} == file ]] && sel=$(( i - 1 ))
    done
    (( sel >= 0 )) || exit 2
    _DLS_SEL=$sel
    _DLS_DONE=0
    _dls_draw() { : }
    _dls_handle_key shift-enter
    [[ -z $_DLS_EXIT_KEY ]] || exit 3
    [[ -z $_DLS_EXIT_ACTION ]] || exit 4
    (( _DLS_DONE == 0 )) || exit 5
    exit 0
  ) || file_rc=$?
  if (( file_rc )); then
    _dnav_test_fail "quit-dir on a file records nothing (rc=$file_rc)"
  else
    _dnav_test_pass "quit-dir on a file records nothing"
  fi

  (
    _dls_draw() { : }
    _DLS_VIS=()
    _DLS_DONE=0
    _DLS_EXIT_KEY=""
    _DLS_EXIT_ACTION=""
    _dls_handle_key enter
    (( _DLS_DONE == 0 )) || exit 1
    [[ -z $_DLS_EXIT_KEY ]] || exit 2
    [[ -z $_DLS_EXIT_ACTION ]] || exit 3
    exit 0
  ) || open_rc=$?
  if (( open_rc )); then
    _dnav_test_fail "enter does not record a leave (rc=$open_rc)"
  else
    _dnav_test_pass "enter does not record a leave"
  fi

  typeset -g _DLS_LOG=""
  functions -c _dls_out _dls_out_real
  _dls_out() { _DLS_LOG+="$(printf "$@")"; }

  _DLS_AUTO_CLS=always
  _DLS_EXIT_KEY=esc
  _DLS_EXIT_ACTION=quit
  _DLS_STTY=""
  _DLS_KB_PROTO=0
  _DLS_TTY=""
  _DLS_LEFT=0
  _DLS_DRAWN=4
  _DLS_ROWS=20
  _DLS_DRAW_ROW=1
  _DLS_LOG=""
  _dls_leave
  log_once="$_DLS_LOG"
  _dls_leave
  assert_eq "$_DLS_LOG" "$log_once" "a second leave does not write again"
  assert_contains "$_DLS_LOG" $'\e[H\e[2J' "always clears the visible page"
  assert_contains "$_DLS_LOG" $'\e[?25h' "always still shows the cursor"
  if [[ $_DLS_LOG == *$'\e[5;1H'* ]]; then
    _dnav_test_fail "always still moved below the grid"
  else
    _dnav_test_pass "always skips the cursor move"
  fi
  assert_eq "$_DLS_DRAWN" "0" "leave forgets the painted lines"
  assert_eq "$_DLS_LEFT" "1" "leave marks itself done"

  _DLS_AUTO_CLS=off
  _DLS_LEFT=0
  _DLS_DRAWN=4
  _DLS_ROWS=20
  _DLS_DRAW_ROW=1
  _DLS_STTY=""
  _DLS_KB_PROTO=0
  _DLS_LOG=""
  _dls_leave
  assert_contains "$_DLS_LOG" $'\e[5;1H' "off parks the cursor under the grid"
  if [[ $_DLS_LOG == *$'\e[H\e[2J'* ]]; then
    _dnav_test_fail "off cleared the page"
  else
    _dnav_test_pass "off does not clear"
  fi

  _DLS_AUTO_CLS=always
  _DLS_LEFT=0
  _DLS_DRAWN=0
  _DLS_ROWS=20
  _DLS_LOG=""
  _dls_leave
  if [[ $_DLS_LOG == *$'\e[H\e[2J'* ]]; then
    _dnav_test_fail "always cleared when nothing was painted"
  else
    _dnav_test_pass "always skips a blank start"
  fi

  functions -c _dls_out_real _dls_out
  unfunction _dls_out_real
  _DLS_LOG=""
  _DLS_LEFT=0
  _DLS_DONE=0
  _DLS_EXIT_KEY=""
  _DLS_EXIT_ACTION=""
  _dls_config_defaults
}

test_dls_shift_enter_ls() {
  local rc="$DLS_TMP/rc-shift-ls" mark="$DLS_TMP/follow" follow_rc=0 warns
  _dls_config_defaults
  assert_eq "$_DLS_SHIFT_LS" "off" "shift-enter listing starts off"
  assert_ok _dls_config_set "shift_enter_ls ls"
  assert_eq "$_DLS_SHIFT_LS" "ls" "shift_enter_ls ls"
  assert_ok _dls_config_set "shift_enter_ls true"
  assert_eq "$_DLS_SHIFT_LS" "ls" "true means ls"
  assert_ok _dls_config_set "shift_enter_ls dls"
  assert_eq "$_DLS_SHIFT_LS" "dls" "shift_enter_ls dls"
  assert_ok _dls_config_set "shift_enter_ls none"
  assert_eq "$_DLS_SHIFT_LS" "off" "none means off"
  assert_fail _dls_config_set "shift_enter_ls nope"
  assert_eq "$_DLS_SHIFT_LS" "off" "a bad value keeps off"
  print -r -- "set shift_enter_ls ls" > "$rc"
  print -r -- "set shift_enter_ls nope" >> "$rc"
  { _dls_config_load "$rc" } 2>/dev/null
  assert_eq "$_DLS_SHIFT_LS" "ls" "a bad rc line keeps the earlier listing"
  warns="${(j: :)_DLS_RC_WARN}"
  assert_contains "$warns" "bad set" "a bad shift_enter_ls is reported"

  (
    _dls_run_ls() { print -rn -- ls > "$mark"; }
    dls() { print -rn -- dls > "$mark"; return 4; }
    : > "$mark"
    _DLS_SHIFT_LS=off
    _DLS_EXIT_KEY=shift-enter
    _DLS_SCRIPT=1
    _dls_shift_enter_follow 0
    [[ ! -s $mark ]] || exit 1
    _DLS_SHIFT_LS=ls
    _DLS_EXIT_KEY=esc
    _dls_shift_enter_follow 0
    [[ ! -s $mark ]] || exit 2
    _DLS_EXIT_KEY=shift-enter
    _dls_shift_enter_follow 130
    [[ ! -s $mark ]] || exit 3
    _dls_shift_enter_follow 0
    [[ $(<"$mark") == ls ]] || exit 4
    : > "$mark"
    _DLS_SHIFT_LS=dls
    _dls_shift_enter_follow 0
    [[ $(<"$mark") == dls ]] || exit 5
    [[ $_DLS_SCRIPT == 1 ]] || exit 6
    exit 0
  ) || follow_rc=$?
  if (( follow_rc )); then
    _dnav_test_fail "shift-enter listing follows the key (rc=$follow_rc)"
  else
    _dnav_test_pass "shift-enter listing follows the key"
  fi

  _DLS_EXIT_KEY=""
  _DLS_SCRIPT=0
  _dls_config_defaults
}

run_test test_dls_filter
run_test test_dls_ls_flags
run_test test_dls_shift_enter
run_test test_dls_auto_cls
run_test test_dls_shift_enter_ls
dnav_test_finish
