#!/usr/bin/env bash
# install.sh — zsh install (~/.local/share/dnav, ~/.config/dnav, zshrc hook)
#
#   ./install.sh                 default
#   ./install.sh --update        refresh scripts; merge new config keys
#   ./install.sh --prefix DIR    script dir
#   ./install.sh --config DIR    config dir
#   ./install.sh --no-rc         skip zshrc
#   ./install.sh --force-config  overwrite config/folders/jumps
#   ./install.sh --uninstall     remove scripts + hook (keeps config)
#   ./install.sh -h
#
set -euo pipefail

VERSION="1.1"
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
UPDATE=0

# Files shipped with the package (relative to PACKAGE_DIR)
PACKAGE_FILES=(dnav dfile djump dsearch dsearch-index dindexer dnav-about dnav-update jumps)

# Markers for idempotent .zshrc edits
RC_BEGIN="# >>> dnav >>>"
RC_END="# <<< dnav <<<"

die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

# Args
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
    --update|--upgrade) UPDATE=1; shift ;;
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

# When this script lives next to dnav (installed copy), zsh/ is not here.
# Resolve the git/source tree so --update still works.
resolve_source() {
  local src="" line
  if [[ -d "$PACKAGE_DIR" && -f "$PACKAGE_DIR/dnav" ]]; then
    return 0
  fi
  if [[ -n "${DNAV_UPDATE_FROM:-}" ]]; then
    src="$DNAV_UPDATE_FROM"
  elif [[ -f "$SCRIPT_DIR/.source" ]]; then
    IFS= read -r line < "$SCRIPT_DIR/.source" || line=""
    src="$line"
  elif [[ -f "$PREFIX/.source" ]]; then
    IFS= read -r line < "$PREFIX/.source" || line=""
    src="$line"
  elif [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/DNav/zsh" ]]; then
    src="${XDG_DATA_HOME:-$HOME/.local/share}/DNav"
  elif [[ -d "$HOME/.local/share/DNav/zsh" ]]; then
    src="$HOME/.local/share/DNav"
  fi
  src="${src/#\~/$HOME}"
  if [[ -n "$src" && -f "$src/zsh/dnav" ]]; then
    SCRIPT_DIR="$src"
    PACKAGE_DIR="$SCRIPT_DIR/zsh"
    return 0
  fi
  die "cannot find DNav source (zsh/dnav). Run from the repo, or set DNAV_UPDATE_FROM=/path/to/DNav"
}

write_source_pointer() {
  printf '%s\n' "$SCRIPT_DIR" > "$PREFIX/.source"
}

check_package() {
  resolve_source
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
  write_source_pointer
  copy_shell_hooks
  zcompile_zsh
  ok "scripts → $PREFIX"
}

copy_shell_hooks() {
  local src="$SCRIPT_DIR/shell" dest="$PREFIX/shell" f
  [[ -d $src ]] || src="${PACKAGE_DIR%/zsh}/shell"
  [[ -d $src ]] || return 0
  mkdir -p -- "$dest"
  if [[ "$(cd -- "$src" && pwd)" == "$(cd -- "$dest" && pwd)" ]]; then
    info "hooks  $dest"
    return 0
  fi
  for f in dnav.sh dnav.zsh dnav.fish dnav.ps1; do
    [[ -f $src/$f ]] || continue
    install -m 0644 -- "$src/$f" "$dest/$f"
  done
  info "hooks  $dest"
}

zcompile_zsh() {
  command -v zsh >/dev/null 2>&1 || return 0
  zsh -f -c '
    emulate -L zsh
    local f
    for f in dnav djump dfile dsearch dsearch-index dindexer dnav-about dnav-update; do
      [[ -f $1/$f ]] || continue
      zcompile -U -- "$1/$f" 2>/dev/null || true
    done
  ' zsh "$PREFIX" || true
}

# If a bash prefix is already installed, refresh it too. Never overwrite config.
update_other_shells() {
  local bash_dest="${XDG_DATA_HOME:-$HOME/.local/share}/dnav-bash"
  local f
  if [[ -d "$bash_dest" && -d "$SCRIPT_DIR/bash" ]]; then
    for f in dnav dfile djump dsearch jumps; do
      [[ -f "$SCRIPT_DIR/bash/$f" ]] || continue
      install -m 0644 -- "$SCRIPT_DIR/bash/$f" "$bash_dest/$f"
    done
    chmod 0755 -- "$bash_dest/dnav" 2>/dev/null || true
    ok "bash scripts → $bash_dest"
  fi
}

# ── Seed user config (never clobber unless --force-config) ────────────────
write_default_config() {
  cat > "$CONFIG_DIR/config" <<'EOF'
# DNav settings — edit freely, then: dconfig -r
#
# Colors: names (cyan, blue, …) or ANSI numbers
#   fg: 30–37 / 90–97    bg: 40–47 / 100–107
#   names: black red green yellow blue magenta cyan white
#          bright-red bright-cyan …
color_fg = black
color_bg = cyan

# Brand chip label on the main bar
brand = DNav

# ls -a after a successful select/jump
ls_after = 0
# ls_after_dnav = inherit
# ls_after_djump = inherit
# milliseconds to wait after the path bar before ls (0 = no wait)
ls_after_ms = 0

# dfile: show hidden files/dirs by default (toggle still works with .)
show_hidden = 0
# dfile dir order: alpha | hidden_first
dfile_sort_dirs = alpha
# dfile file order: alpha | ext | dot_first | dot_ext
dfile_sort_files = alpha
# dfile Jump to: folder name max (cuts the end)
dfile_jump_name_max = 20

# Cyan path bar (0 = hide). *_dnav / *_djump override when set
success_bar = 1
# success_bar_dnav = inherit
# success_bar_djump = inherit

# Animate the expand-to-path success bar (0 = instant bar)
success_anim = 1
success_anim_steps = 8
success_anim_ms = 2

# 1 = full line redraw every move; 0 = partial chip repaint
full_redraw = 0

# dsearch roots (space-separated). Empty = $HOME only.
# search_roots = $HOME /opt /mnt

# Directory index for search (dirs.idx under ~/.cache/dnav).
# auto: 1 = rebuild when stale; 0 = only dnav --reindex
index_auto = 1
# when: open = start with dnav; search = wait until search opens
index_when = open
# Hours until the on-disk index is stale. 0 = never (still build if missing)
index_ttl_hours = 24
# If set, auto-index / dnav --reindex import this list instead of walking.
# index_file = ~/.cache/dnav/my-dirs

# Status message auto-clear (ms). 0 = keep until the next message
status_timeout_ms = 3000
# inaccessible_color = red
# inaccessible_icon = 1
EOF
}

# Add any keys the current package knows about; never overwrite existing values.
merge_user_config() {
  local out
  mkdir -p -- "$CONFIG_DIR"
  if [[ ! -f "$CONFIG_DIR/config" ]]; then
    write_default_config
    info "wrote $CONFIG_DIR/config"
    return 0
  fi
  out="$(
    DNAV_CONFIG_DIR="$CONFIG_DIR" zsh -f -c '
      emulate -L zsh
      DNAV_CONFIG_DIR="$1"
      source "$2"
      _dnav_config_merge_defaults
    ' zsh "$CONFIG_DIR" "$PACKAGE_DIR/dnav"
  )" || {
    warn "could not merge $CONFIG_DIR/config"
    return 0
  }
  out="${out##*$'\n'}"
  if [[ "$out" =~ ^[0-9]+$ && "$out" -gt 0 ]]; then
    ok "config +$out new keys (previous values kept) → $CONFIG_DIR/config"
  else
    info "config already current (previous values kept)"
  fi
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
Config      ~/.config
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
# DNav: dKEY jumps now; TUI loads on first \`dnav\` (does not start by itself).
DNAV_DIR=${PREFIX}
if [[ -r \${DNAV_DIR}/shell/dnav.zsh ]]; then
  source \${DNAV_DIR}/shell/dnav.zsh
elif [[ -r \${DNAV_DIR}/dnav ]]; then
  source \${DNAV_DIR}/dnav
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
    if awk -v b="$RC_BEGIN" -v e="$RC_END" '
      $0==b{s=1} $0==e{s=0}
      !s && $0 ~ /^[[:space:]]*dnav([[:space:]]|$)/ { found=1 }
      END { exit !found }
    ' "$ZSHRC"; then
      warn "Found a bare 'dnav' line in $ZSHRC — that auto-runs the TUI on every shell."
      warn "Remove it if you only want DNav available on demand."
    fi
  fi
  hook_other_shells
}

BASHRC="${HOME}/.bashrc"
FISH_RC="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"

hook_file() {
  local rc="$1" extra="$2"
  [[ -n $rc ]] || return 0
  if [[ ! -f $rc ]]; then
    return 0
  fi
  local tmp
  if grep -qF "$RC_BEGIN" "$rc" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v begin="$RC_BEGIN" -v end="$RC_END" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip { print }
    ' "$rc" > "$tmp"
    cat "$tmp" > "$rc"
    rm -f -- "$tmp"
  fi
  {
    printf '\n'
    printf '%s\n' "$RC_BEGIN"
    printf '%s\n' "$extra"
    printf '%s\n' "$RC_END"
  } >> "$rc"
  ok "hooked $rc"
}

hook_other_shells() {
  (( DO_RC )) || return 0
  local posix
  posix=$(cat <<EOF
DNAV_DIR=${PREFIX}
export DNAV_DIR
# zsh uses native functions from .zshrc; skip this hook there.
if [ -z "\${ZSH_VERSION:-}" ] && [ -r "\${DNAV_DIR}/shell/dnav.sh" ]; then
  . "\${DNAV_DIR}/shell/dnav.sh"
fi
EOF
)
  hook_file "$BASHRC" "$posix"
  if [[ -f ${HOME}/.profile ]]; then
    hook_file "${HOME}/.profile" "$posix"
  fi
  if command -v fish >/dev/null 2>&1 || [[ -f $FISH_RC ]]; then
    mkdir -p -- "$(dirname -- "$FISH_RC")"
    [[ -f $FISH_RC ]] || : > "$FISH_RC"
    hook_file "$FISH_RC" "set -gx DNAV_DIR ${PREFIX}"$'\n'"if test -r \$DNAV_DIR/shell/dnav.fish"$'\n'"    source \$DNAV_DIR/shell/dnav.fish"$'\n'"end"
  fi
}

unhook_file() {
  local rc="$1"
  [[ -f $rc ]] || return 0
  grep -qF "$RC_BEGIN" "$rc" 2>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$RC_BEGIN" -v end="$RC_END" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  cat "$tmp" > "$rc"
  rm -f -- "$tmp"
}

remove_rc() {
  if rc_has_block; then
    unhook_file "$ZSHRC"
    ok "removed hook from $ZSHRC"
  else
    info "no dnav block in $ZSHRC"
  fi
  unhook_file "${HOME}/.bashrc"
  unhook_file "${HOME}/.profile"
  unhook_file "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
}

uninstall() {
  printf 'Uninstalling DNav…\n'
  remove_rc
  if [[ -d "$PREFIX" ]]; then
    local f
    for f in "${PACKAGE_FILES[@]}" install.sh .source; do
      rm -f -- "$PREFIX/$f" "$PREFIX/$f.zwc"
    done
    rm -rf -- "$PREFIX/shell"
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

  if [[ $UPDATE -eq 1 ]]; then
    printf 'Updating DNav %s…\n' "$VERSION"
    info "source  $PACKAGE_DIR"
    info "prefix  $PREFIX"
    info "config  $CONFIG_DIR (values kept, new keys merged)"
    printf '\n'
    install_scripts
    update_other_shells
    install_rc
    merge_user_config
    printf '\n'
    ok "DNav updated"
    printf '\nReload:  exec zsh    or    source %s/dnav\n' "$PREFIX"
    info "From the shell:  dnav --update"
    printf '\n'
    exit 0
  fi

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
  info "2. Try:           dnav       dnav --help       dconfig -p"
  info "3. Jump:          dhome      dhelp       djump -l"
  info "4. Edit config:   dconfig -e   or   About → Settings in dnav"
  info "5. Later updates: dnav --update    or    ./install.sh --update"
  printf '\nConfig files:\n'
  info "$CONFIG_DIR/config"
  info "$CONFIG_DIR/folders"
  info "$CONFIG_DIR/jumps"
  printf '\n'
}

main
