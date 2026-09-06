# zshrc stub: dKEY wrappers + dnav/dconfig/djump load files on first use.
# Does not source djump or the TUI at shell start.

[[ -n ${_DNAV_ZSH_STUB:-} ]] && return 0
_DNAV_ZSH_STUB=1
: "${DNAV_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dnav}"

_dnav_stub_source_djump() {
  [[ -r $DNAV_DIR/djump ]] || return 1
  source "$DNAV_DIR/djump"
}

djump() {
  _dnav_stub_source_djump || {
    print -u2 -- "dnav: missing $DNAV_DIR/djump"
    return 1
  }
  djump "$@"
}

dhelp() {
  _dnav_stub_source_djump || {
    print -u2 -- "dnav: missing $DNAV_DIR/djump"
    return 1
  }
  dhelp "$@"
}

# Bind dKEY from the jumps file without loading djump.
_dnav_stub_bind_keys() {
  emulate -L zsh
  setopt localoptions no_extended_glob
  local f line key cmd kind
  f="${DNAV_JUMPS:-}"
  if [[ -z $f || ! -f $f ]]; then
    f="${DNAV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnav}/jumps"
  fi
  [[ -f $f ]] || f="$DNAV_DIR/jumps"
  [[ -f $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z $line || $line == \#* ]] && continue
    key="${line%%[[:space:]]*}"
    [[ $key =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || continue
    cmd="d${key}"
    case $cmd in
      dnav|djump|dconfig|dhelp) continue ;;
    esac
    if (( $+functions[$cmd] )); then
      continue
    fi
    kind="$(whence -w -- "$cmd" 2>/dev/null)"
    kind="${kind#*: }"
    case $kind in
      alias|builtin|command) continue ;;
    esac
    eval "${cmd}() { (( \$+functions[_djump_goto] )) || source \"\$DNAV_DIR/djump\"; _djump_goto ${(q)key}; }"
  done < "$f"
}

_dnav_stub_bind_keys

dnav() {
  unfunction dnav dconfig 2>/dev/null
  source "$DNAV_DIR/dnav"
  dnav "$@"
}

dconfig() {
  unfunction dnav dconfig 2>/dev/null
  source "$DNAV_DIR/dnav"
  dconfig "$@"
}
