#!/usr/bin/env bash
# install.sh — install DNav for zsh
#
# Usage:
#   ./install.sh                 # install to ~/.local/share/dnav + seed config + hook zshrc
#   ./install.sh --prefix DIR    # install scripts under DIR (default: $XDG_DATA_HOME/dnav)
#   ./install.sh --config DIR    # config dir (default: $XDG_CONFIG_HOME/dnav)
#   ./install.sh --no-rc         # skip shell rc edits
#   ./install.sh --force-config  # overwrite config/folders/jumps with package defaults
#   ./install.sh --uninstall     # remove install + rc hook (keeps user config)
#   ./install.sh -h
#
set -euo pipefail

VERSION="1.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Shell-specific package lives under zsh/ (install.sh stays at repo root)
PACKAGE_DIR="$SCRIPT_DIR/zsh"

# Defaults
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/dnav"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dnav"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
DO_RC=1
FORCE_CONFIG=0
UNINSTALL=0

# Files shipped with the package (relative to PACKAGE_DIR)
PACKAGE_FILES=(dnav dfile djump dsearch jumps)

# Markers for idempotent .zshrc edits
RC_BEGIN="# >>> dnav >>>"
RC_END="# <<< dnav <<<"

die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

# ── Args ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a path"
      PREFIX="$2"; shift 2 ;;
    --config)
      [[ $# -ge 2 ]] || die "--config needs a path"
      CONFIG_DIR="$2"; shift 2 ;;
    --no-rc) DO_RC=0; shift ;;
    --force-config) FORCE_CONFIG=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# Expand ~
PREFIX="${PREFIX/#\~/$HOME}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
ZSHRC="${ZSHRC/#\~/$HOME}"

require_zsh() {
  if ! command -v zsh >/dev/null 2>&1; then
    die "zsh is required (DNav is a zsh tool). Install zsh and re-run."
  fi
}

check_package() {
  [[ -d "$PACKAGE_DIR" ]] || die "missing package directory: $PACKAGE_DIR"
  local f
  for f in "${PACKAGE_FILES[@]}"; do
    [[ -f "$PACKAGE_DIR/$f" ]] || die "missing package file: $PACKAGE_DIR/$f"
  done
}

# ── Install scripts ───────────────────────────────────────────────────────
install_scripts() {
  mkdir -p -- "$PREFIX"
  local f
  for f in "${PACKAGE_FILES[@]}"; do
    install -m 0644 -- "$PACKAGE_DIR/$f" "$PREFIX/$f"
  done
  # dnav can be executed directly; modules are sourced
  chmod 0755 -- "$PREFIX/dnav"
  # Ship installer next to the app when prefix ≠ source tree
  if [[ "$SCRIPT_DIR" != "$PREFIX" && -f "$SCRIPT_DIR/install.sh" ]]; then
    install -m 0755 -- "$SCRIPT_DIR/install.sh" "$PREFIX/install.sh"
  elif [[ -f "$PREFIX/install.sh" ]]; then
    chmod 0755 -- "$PREFIX/install.sh"
  fi
  ok "scripts → $PREFIX"
}

# ── Seed user config (never clobber unless --force-config) ────────────────
write_default_config() {
  cat > "$CONFIG_DIR/config" <<'EOF'
# DNav settings — edit freely, then: dconfig -r
#
# Colors: names (cyan, blue, …) or ANSI numbers
#   fg: 30–37 / 90–97    bg: 40–47 / 100–107
color_fg = black
color_bg = cyan

# Brand chip label on the main bar
brand = DNav

# ls -a after a successful select/jump
ls_after = 0

# dfile: show hidden files/dirs by default (toggle still works with .)
show_hidden = 0

# Animate the expand-to-path success bar (0 = instant bar)
success_anim = 1

# 1 = full line redraw every move; 0 = partial chip repaint
full_redraw = 0

# dsearch roots (space-separated). Empty = built-in defaults
# search_roots = $HOME /opt /mnt
EOF
}

write_default_folders() {
  cat > "$CONFIG_DIR/folders" <<'EOF'
# Main dnav bar — one entry per line:  Label   path
# Paths: ~ expands. About is always added by dnav (not listed here).
#
# Label     path
Home        ~
Docs        ~/Documents
Down        ~/Downloads
EbSync      ~/Eb_Transfer
Projects    ~/Projects
Config      ~/.config
Apps        ~/Apps
Share       ~/.local/share
EOF
}

seed_config() {
  mkdir -p -- "$CONFIG_DIR"

  if [[ $FORCE_CONFIG -eq 1 || ! -f "$CONFIG_DIR/config" ]]; then
    write_default_config
    info "wrote $CONFIG_DIR/config"
  else
    info "keep  $CONFIG_DIR/config (exists)"
  fi

  if [[ $FORCE_CONFIG -eq 1 || ! -f "$CONFIG_DIR/folders" ]]; then
    write_default_folders
    info "wrote $CONFIG_DIR/folders"
  else
    info "keep  $CONFIG_DIR/folders (exists)"
  fi

  if [[ $FORCE_CONFIG -eq 1 || ! -f "$CONFIG_DIR/jumps" ]]; then
    if [[ -f "$PACKAGE_DIR/jumps" ]]; then
      install -m 0644 -- "$PACKAGE_DIR/jumps" "$CONFIG_DIR/jumps"
    else
      cat > "$CONFIG_DIR/jumps" <<'EOF'
# djump table — key becomes shell command dKEY (home → dhome)
# Format:  key   path
home      ~
bk        ..
con       ~/.config
doc       ~/Documents
down      ~/Downloads
proj      ~/Projects
share     ~/.local/share
EOF
    fi
    info "wrote $CONFIG_DIR/jumps"
  else
    info "keep  $CONFIG_DIR/jumps (exists)"
  fi

  ok "config → $CONFIG_DIR"
}

# ── Shell rc hook ─────────────────────────────────────────────────────────
rc_block() {
  # PREFIX is expanded at install time so the path is concrete in .zshrc
  cat <<EOF
$RC_BEGIN
# DNav — navigation TUI + dKEY jumps (https://github.com/Ebsolas/DNav)
# Does not auto-run the TUI; type \`dnav\` when you want it.
if [[ -r ${PREFIX}/dnav ]]; then
  source ${PREFIX}/dnav
fi
$RC_END
EOF
}

rc_has_block() {
  [[ -f "$ZSHRC" ]] && grep -qF "$RC_BEGIN" "$ZSHRC" 2>/dev/null
}

install_rc() {
  if [[ $DO_RC -eq 0 ]]; then
    info "skipping shell rc (--no-rc)"
    return 0
  fi

  if [[ ! -f "$ZSHRC" ]]; then
    touch -- "$ZSHRC"
    info "created $ZSHRC"
  fi

  if rc_has_block; then
    # Refresh block in place (handles prefix changes)
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2016
    awk -v begin="$RC_BEGIN" -v end="$RC_END" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip { print }
    ' "$ZSHRC" > "$tmp"
    cat "$tmp" > "$ZSHRC"
    rm -f -- "$tmp"
  fi

  {
    printf '\n'
    rc_block
  } >> "$ZSHRC"

  ok "hooked $ZSHRC"

  # Nudge if an old bare `dnav` auto-start remains outside our block
  if grep -nE '^[[:space:]]*dnav([[:space:]]|$)' "$ZSHRC" 2>/dev/null \
      | grep -vF "$RC_BEGIN" >/dev/null 2>&1; then
    # Only warn if a line is exactly calling dnav and not inside comments we just wrote
    if awk -v b="$RC_BEGIN" -v e="$RC_END" '
      $0==b{s=1} $0==e{s=0}
      !s && $0 ~ /^[[:space:]]*dnav([[:space:]]|$)/ { found=1 }
      END { exit !found }
    ' "$ZSHRC"; then
      warn "Found a bare 'dnav' line in $ZSHRC — that auto-runs the TUI on every shell."
      warn "Remove it if you only want DNav available on demand."
    fi
  fi
}

remove_rc() {
  [[ -f "$ZSHRC" ]] || return 0
  if ! rc_has_block; then
    info "no dnav block in $ZSHRC"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$RC_BEGIN" -v end="$RC_END" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$ZSHRC" > "$tmp"
  # trim trailing blank lines introduced by removal (best-effort)
  cat "$tmp" > "$ZSHRC"
  rm -f -- "$tmp"
  ok "removed hook from $ZSHRC"
}

uninstall() {
  printf 'Uninstalling DNav…\n'
  remove_rc
  if [[ -d "$PREFIX" ]]; then
    local f
    for f in "${PACKAGE_FILES[@]}" install.sh; do
      rm -f -- "$PREFIX/$f"
    done
    # Remove dir if empty
    rmdir -- "$PREFIX" 2>/dev/null || info "left $PREFIX (not empty or in use)"
    ok "removed scripts from $PREFIX"
  fi
  info "kept user config at $CONFIG_DIR (delete manually if you want)"
  printf '\nDone. Open a new shell (or: exec zsh) so the old source is dropped.\n'
}

# ── Main ──────────────────────────────────────────────────────────────────
main() {
  if [[ $UNINSTALL -eq 1 ]]; then
    uninstall
    exit 0
  fi

  require_zsh
  check_package

  printf 'Installing DNav %s…\n' "$VERSION"
  info "source  $PACKAGE_DIR"
  info "prefix  $PREFIX"
  info "config  $CONFIG_DIR"
  printf '\n'

  install_scripts
  seed_config
  install_rc

  printf '\n'
  ok "DNav installed"
  printf '\nNext steps:\n'
  info "1. Reload shell:  exec zsh   (or open a new terminal)"
  info "2. Try:           dnav       dhelp       dconfig -p"
  info "3. Jump:          dhome      dproj       djump -l"
  info "4. Edit config:   dconfig -e   or   About → Settings in dnav"
  printf '\nConfig files:\n'
  info "$CONFIG_DIR/config"
  info "$CONFIG_DIR/folders"
  info "$CONFIG_DIR/jumps"
  printf '\n'
}

main
