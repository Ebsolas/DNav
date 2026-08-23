# POSIX hook for bash/ash/dash/ksh. Source this file; do not execute.
# Spawns `zsh -f` only when you run dnav/djump/dKEY — not at shell startup.
#
#   DNAV_DIR=/path/to/dnav . /path/to/dnav/shell/dnav.sh

[ -n "${ZSH_VERSION:-}" ] && return 0
[ -n "${_DNAV_HOOKED:-}" ] && return 0
_DNAV_HOOKED=1

: "${DNAV_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dnav}"
_DNAV_BOUND_KEYS=""

_dnav_have_zsh() {
  command -v zsh >/dev/null 2>&1
}

_dnav_jumps_file() {
  if [ -n "${DNAV_JUMPS:-}" ] && [ -f "$DNAV_JUMPS" ]; then
    printf '%s\n' "$DNAV_JUMPS"
  elif [ -f "${DNAV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnav}/jumps" ]; then
    printf '%s\n' "${DNAV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnav}/jumps"
  elif [ -f "$DNAV_DIR/jumps" ]; then
    printf '%s\n' "$DNAV_DIR/jumps"
  fi
}

_dnav_cmd() {
  if ! _dnav_have_zsh; then
    printf 'dnav: zsh not found\n' >&2
    return 127
  fi
  if [ ! -f "$DNAV_DIR/dnav" ]; then
    printf 'dnav: missing %s/dnav\n' "$DNAV_DIR" >&2
    return 1
  fi
  _dnav_rf="${TMPDIR:-/tmp}/dnav.$$"
  i=0
  while [ -e "$_dnav_rf" ]; do
    i=$((i + 1))
    _dnav_rf="${TMPDIR:-/tmp}/dnav.$$.$i"
  done
  : > "$_dnav_rf" || return 1
  _dnav_st=0
  if [ -t 0 ] && [ -t 1 ] && [ -c /dev/tty ] 2>/dev/null; then
    DNAV_RESULT_FILE=$_dnav_rf zsh -f -c '
      source -- "$1/dnav" || exit 1
      cmd=$2
      shift 2
      "$cmd" "$@"
    ' dnav "$DNAV_DIR" "$@" </dev/tty >/dev/tty || _dnav_st=$?
  else
    DNAV_RESULT_FILE=$_dnav_rf zsh -f -c '
      source -- "$1/dnav" || exit 1
      cmd=$2
      shift 2
      "$cmd" "$@"
    ' dnav "$DNAV_DIR" "$@" || _dnav_st=$?
  fi
  _dnav_dest=""
  if [ -s "$_dnav_rf" ]; then
    _dnav_dest=$(cat "$_dnav_rf")
  fi
  rm -f "$_dnav_rf"
  if [ -n "$_dnav_dest" ]; then
    cd -- "$_dnav_dest" || return
  fi
  return "$_dnav_st"
}

dnav() { _dnav_cmd dnav "$@"; }
djump() {
  _dnav_cmd djump "$@"
  _dnav_st=$?
  case ${1:-} in
    add|edit|remove|rm|delete|del|-r|--reload) _dnav_bind_jumps ;;
  esac
  return "$_dnav_st"
}
dconfig() { _dnav_cmd dconfig "$@"; }
dhelp() { _dnav_cmd dhelp "$@"; }

_dnav_bind_jumps() {
  _k=""
  for _k in $_DNAV_BOUND_KEYS; do
    unset -f "d${_k}" 2>/dev/null || true
  done
  _DNAV_BOUND_KEYS=""
  _f=$(_dnav_jumps_file)
  [ -n "$_f" ] && [ -f "$_f" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _line=${_line#"${_line%%[![:space:]]*}"}
    [ -z "$_line" ] && continue
    case $_line in \#*) continue ;; esac
    _key=${_line%%[[:space:]]*}
    case d$_key in
      dnav|djump|dconfig|dhelp) continue ;;
    esac
    case $_key in
      *[!A-Za-z0-9_]* | [0-9]*) continue ;;
    esac
    eval "d${_key}() { _dnav_cmd djump ${_key}; }"
    _DNAV_BOUND_KEYS="${_DNAV_BOUND_KEYS} ${_key}"
  done < "$_f"
}

_dnav_bind_jumps
