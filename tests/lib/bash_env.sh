# Isolated environment for sourcing bash DNav modules in tests.
# Does not touch the developer's real ~/.config/dnav.

_DNAV_TEST_LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DNAV_REPO_ROOT="$(cd -- "$_DNAV_TEST_LIB/../.." && pwd)"
DNAV_BASH_DIR="$DNAV_REPO_ROOT/bash"

# Temp root for this process (created once per test file if missing)
: "${DNAV_TEST_TMP:=}"

# IMPORTANT: do not call this via $(...) — that runs in a subshell and loses DNAV_TEST_TMP.
dnav_test_mktemp() {
  if [[ -z ${DNAV_TEST_TMP:-} || ! -d ${DNAV_TEST_TMP:-} ]]; then
    DNAV_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dnav-test.XXXXXX")"
    # shellcheck disable=SC2064
    trap 'rm -rf -- "${DNAV_TEST_TMP:-}"' EXIT
  fi
}

# Build a private HOME + XDG layout and source bash/dnav (loads siblings).
# Sets globals: DNAV_TEST_HOME DNAV_TEST_CONFIG DNAV_TEST_CACHE DNAV_DIR
dnav_test_setup_bash() {
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
  # Prevent accidental use of developer DNAV_JUMPS / SEARCH_ROOTS
  unset DNAV_JUMPS DNAV_SEARCH_ROOTS DNAV_SEARCH_LIGHT 2>/dev/null || true

  # Seed minimal config so source-time load is deterministic
  cat > "$config/config" <<'EOF'
color_fg = black
color_bg = cyan
brand = TestNav
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
  cat > "$config/jumps" <<EOF
home      ~
doc       ~/Documents
proj      ~/Projects
apps      ~/Apps
EOF

  DNAV_TEST_HOME="$home"
  DNAV_TEST_CONFIG="$config"
  DNAV_TEST_CACHE="$cache"

  # Fresh shell state for modules
  # shellcheck disable=SC1091
  source "$DNAV_BASH_DIR/dnav"

  # Silence success bar animation / path prints in pure unit tests when needed
  DNAV_CFG_SUCCESS_ANIM=0
}

# Write a small synthetic directory index for dsearch tests (avoids full-tree find).
# Paths must exist on disk for open/cd tests; fuzzy filter only needs text lines.
dnav_test_write_index() {
  local idx="${1:-}"
  if [[ -z $idx ]]; then
    idx="${DNAV_TEST_CACHE:-$XDG_CACHE_HOME/dnav}/dirs.idx"
  fi
  mkdir -p "$(dirname -- "$idx")"
  # Prefer real dirs under test HOME so pin/open can work
  {
    printf '%s\n' "$HOME"
    printf '%s\n' "$HOME/Documents"
    printf '%s\n' "$HOME/Downloads"
    printf '%s\n' "$HOME/Projects"
    printf '%s\n' "$HOME/Apps"
    printf '%s\n' "$HOME/Apps/ChaTTY"
    printf '%s\n' "$HOME/Apps/ChaTTY/docs"
    printf '%s\n' "$HOME/Projects/dnav-demo"
    printf '%s\n' "/usr/share/doc"
    printf '%s\n' "/usr/share/doc/bash"
    printf '%s\n' "/tmp/dnav-synthetic-only"
  } > "$idx"
  # Ensure a few extra real paths for richer fuzzy tests
  mkdir -p "$HOME/Apps/ChaTTY/docs" "$HOME/Projects/dnav-demo" 2>/dev/null || true
  DNAV_TEST_INDEX="$idx"
}

# Prepare dsearch session state without interactive TUI.
# Sets DNAV_TEST_INDEX; does not print (safe under set -e).
dnav_test_dsearch_session() {
  dnav_test_write_index
  mkdir -p -- "$DNAV_TEST_TMP"
  _dsearch_tmpdir="$(mktemp -d "$DNAV_TEST_TMP/dsearch-sess.XXXXXX")"
  _dsearch_prev_query=""
  _dsearch_cand_stack=()
  declare -gA _dsearch_cand_stack 2>/dev/null || true
  _dsearch_matches=()
  _dsearch_sel=0
  _dsearch_q=""
  _dsearch_focus=list
  _dsearch_view=search
  _DSEARCH_INDEX_STATE=done
  touch -- "$DNAV_TEST_INDEX" 2>/dev/null || true
}
