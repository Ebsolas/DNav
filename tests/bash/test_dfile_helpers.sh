#!/usr/bin/env bash
# dfile pure helpers (no full TUI)
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/bash_env.sh
source "$ROOT/tests/lib/bash_env.sh"

dnav_test_setup_bash

test_dfile_available() {
  assert_ok _dfile_available
}

test_dfile_functions_exist() {
  local f
  for f in _dfile_available _dfile_enter _dfile_list _dfile_paint_strip; do
    if declare -f "$f" >/dev/null 2>&1; then
      _dnav_test_pass "defined $f"
    else
      _dnav_test_fail "missing $f"
    fi
  done
}

# If lock/helpers exist (parity with zsh), exercise them lightly.
test_dfile_optional_lock_helpers() {
  if declare -f _dfile_is_locked >/dev/null 2>&1; then
    # unreadable dir simulation is OS-dependent; just call on HOME
    _dfile_is_locked "$HOME" || true
    _dnav_test_pass "lock helper callable"
  else
    skip_test "no lock helpers in this bash dfile yet"
  fi
}

run_test test_dfile_available
run_test test_dfile_functions_exist
run_test test_dfile_optional_lock_helpers
dnav_test_finish
