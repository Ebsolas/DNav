# Isolated environment for sourcing zsh DNav modules in tests.

_DNAV_TEST_LIB="${0:A:h}"
# When sourced, $0 may be the test file — prefer BASH-style via funcstack if needed.
if [[ -n ${funcfiletrace[1]:-} ]]; then
  # zsh: when this file is sourced, use its path from the first source frame if available
  :
fi
# Resolve lib dir from this file: tests/lib/zsh_env.zsh
if [[ ${(%):-%x} != '%x' && -n ${(%):-%x} ]]; then
  _DNAV_TEST_LIB="${${(%):-%x}:A:h}"
elif [[ -n ${ZSH_ARGZERO:-} && $ZSH_ARGZERO == *zsh_env.zsh ]]; then
  _DNAV_TEST_LIB="${ZSH_ARGZERO:A:h}"
fi

# Fallback: walk from caller if still wrong
if [[ ! -f $_DNAV_TEST_LIB/zsh_assert.zsh ]]; then
  _DNAV_TEST_LIB="${0:A:h}"
fi
if [[ ! -f $_DNAV_TEST_LIB/zsh_assert.zsh && -n ${funcsourcetrace[1]:-} ]]; then
  local _frame="${funcsourcetrace[1]%%:*}"
  [[ -n $_frame ]] && _DNAV_TEST_LIB="${_frame:A:h}"
fi

typeset -g DNAV_REPO_ROOT="${_DNAV_TEST_LIB:A:h:h}"
typeset -g DNAV_ZSH_DIR="$DNAV_REPO_ROOT/zsh"
typeset -g DNAV_TEST_TMP=""
typeset -g DNAV_TEST_HOME=""
typeset -g DNAV_TEST_CONFIG=""
typeset -g DNAV_TEST_CACHE=""
typeset -g DNAV_TEST_INDEX=""

dnav_test_mktemp() {
  if [[ -z ${DNAV_TEST_TMP:-} || ! -d ${DNAV_TEST_TMP:-} ]]; then
    DNAV_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dnav-zsh-test.XXXXXX")"
    # shellcheck disable=SC2064
    trap 'rm -rf -- "${DNAV_TEST_TMP:-}"' EXIT
  fi
}

# Build private HOME/XDG and source zsh/dnav (+ siblings).
dnav_test_setup_zsh() {
  local home config cache
  dnav_test_mktemp
  home="$DNAV_TEST_TMP/home"
  config="$DNAV_TEST_TMP/config/dnav"
  cache="$DNAV_TEST_TMP/cache/dnav"
  mkdir -p "$home/Documents" "$home/Downloads" "$home/Projects" "$home/Apps" \
           "$home/.config" "$config" "$cache"

  export HOME="$home"
  export XDG_CONFIG_HOME="$DNAV_TEST_TMP/config"
  export XDG_CACHE_HOME="$DNAV_TEST_TMP/cache"
  export DNAV_CONFIG_DIR="$config"
  unset DNAV_JUMPS DNAV_SEARCH_ROOTS DNAV_SEARCH_LIGHT 2>/dev/null || true

  cat > "$config/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = ZshTestNav
ls_after = 0
show_hidden = 0
success_anim = 0
full_redraw = 0
EOF
  cat > "$config/folders" <<'EOF'
Home        ~
Docs        ~/Documents
Projects    ~/Projects
EOF
  cat > "$config/jumps" <<'EOF'
home      ~
doc       ~/Documents
proj      ~/Projects
apps      ~/Apps
EOF

  DNAV_TEST_HOME="$home"
  DNAV_TEST_CONFIG="$config"
  DNAV_TEST_CACHE="$cache"

  # dnav config parsers use ${line%%#*} — fails under EXTENDED_GLOB.
  unsetopt extended_glob
  setopt no_err_return

  # shellcheck disable=SC1091
  source "$DNAV_ZSH_DIR/dnav"
  DNAV_CFG_SUCCESS_ANIM=0
  # Production leaves dfile/dsearch lazy; tests need their helpers.
  if (( $+functions[_dnav_load_module] )); then
    _dnav_load_module dfile
    _dnav_load_module dsearch
  fi
}

dnav_test_write_index() {
  local idx="${1:-}"
  if [[ -z $idx ]]; then
    idx="${DNAV_TEST_CACHE:-$XDG_CACHE_HOME/dnav}/dirs.idx"
  fi
  mkdir -p "${idx:h}"
  {
    print -r -- "$HOME"
    print -r -- "$HOME/Documents"
    print -r -- "$HOME/Downloads"
    print -r -- "$HOME/Projects"
    print -r -- "$HOME/Apps"
    print -r -- "$HOME/Apps/ChaTTY"
    print -r -- "$HOME/Apps/ChaTTY/docs"
    print -r -- "$HOME/Projects/dnav-demo"
    print -r -- "/usr/share/doc"
    print -r -- "/usr/share/doc/bash"
    print -r -- "/tmp/dnav-synthetic-only"
  } > "$idx"
  mkdir -p "$HOME/Apps/ChaTTY/docs" "$HOME/Projects/dnav-demo" 2>/dev/null || true
  DNAV_TEST_INDEX="$idx"
}

dnav_test_dsearch_session() {
  dnav_test_write_index
  mkdir -p -- "$DNAV_TEST_TMP"
  _dsearch_tmpdir="$(mktemp -d "$DNAV_TEST_TMP/dsearch-sess.XXXXXX")"
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  _dsearch_matches=()
  _dsearch_sel=0
  _dsearch_q=""
  _dsearch_focus=list
  _dsearch_view=search
  _DSEARCH_INDEX_STATE=done
  touch -- "$DNAV_TEST_INDEX" 2>/dev/null || true
}
