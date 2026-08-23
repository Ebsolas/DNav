# zshrc stub: define djump/dKEY now; load the TUI only on first `dnav`.
# Native zsh — no nested zsh, no TUI at shell start.

[[ -n ${_DNAV_ZSH_STUB:-} ]] && return 0
_DNAV_ZSH_STUB=1
: "${DNAV_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dnav}"

[[ -r $DNAV_DIR/djump ]] && source "$DNAV_DIR/djump"

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
