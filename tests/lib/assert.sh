# Minimal assertion helpers for DNav shell tests.
# Source from a test file; do not execute directly.
#
# Counters (global):
#   DNAV_TEST_PASS DNAV_TEST_FAIL DNAV_TEST_SKIP DNAV_TEST_NAME

: "${DNAV_TEST_PASS:=0}"
: "${DNAV_TEST_FAIL:=0}"
: "${DNAV_TEST_SKIP:=0}"
: "${DNAV_TEST_NAME:=}"
: "${DNAV_TEST_FILE:=}"

_dnav_test_fail() {
  local msg="$1"
  DNAV_TEST_FAIL=$((DNAV_TEST_FAIL + 1))
  printf '  FAIL  %s%s\n' "${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }" "$msg" >&2
  return 1
}

_dnav_test_pass() {
  local msg="${1:-}"
  DNAV_TEST_PASS=$((DNAV_TEST_PASS + 1))
  if [[ -n ${DNAV_TEST_VERBOSE:-} ]]; then
    printf '  ok    %s%s\n' "${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }" "$msg"
  fi
  return 0
}

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-values equal}"
  if [[ $actual == "$expected" ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (expected=$(printf %q "$expected") actual=$(printf %q "$actual"))"
  fi
}

assert_ne() {
  local actual="$1" unexpected="$2" msg="${3:-values differ}"
  if [[ $actual != "$unexpected" ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (both=$(printf %q "$actual"))"
  fi
}

assert_ok() {
  local msg="${*: -1}"
  # If last arg looks like a message (when called as assert_ok cmd args... "msg"),
  # callers should prefer: assert_ok "msg" -- cmd args
  # Simple form: assert_ok command [args...]
  if "$@" >/dev/null 2>&1; then
    _dnav_test_pass "ok: $*"
  else
    local rc=$?
    _dnav_test_fail "command failed (rc=$rc): $*"
  fi
}

assert_fail() {
  if "$@" >/dev/null 2>&1; then
    _dnav_test_fail "command unexpectedly succeeded: $*"
  else
    _dnav_test_pass "fails as expected: $*"
  fi
}

assert_status() {
  local want="$1"
  shift
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "$want" "status of: $*"
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains}"
  if [[ $haystack == *"$needle"* ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (missing $(printf %q "$needle") in $(printf %q "$haystack"))"
  fi
}

assert_file() {
  local path="$1" msg="${2:-file exists: $1}"
  if [[ -f $path ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg"
  fi
}

assert_dir() {
  local path="$1" msg="${2:-dir exists: $1}"
  if [[ -d $path ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg"
  fi
}

assert_gt() {
  local a="$1" b="$2" msg="${3:-$a > $b}"
  if (( a > b )); then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (got $a <= $b)"
  fi
}

assert_ge() {
  local a="$1" b="$2" msg="${3:-$a >= $b}"
  if (( a >= b )); then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (got $a < $b)"
  fi
}

# Run a named test function; isolates DNAV_TEST_NAME for reporting.
run_test() {
  local name="$1"
  DNAV_TEST_NAME="$name"
  if [[ -n ${DNAV_TEST_VERBOSE:-} ]]; then
    printf '  RUN   %s\n' "$name"
  fi
  # shellcheck disable=SC2086
  "$name"
  DNAV_TEST_NAME=""
}

skip_test() {
  local reason="${1:-skipped}"
  DNAV_TEST_SKIP=$((DNAV_TEST_SKIP + 1))
  printf '  SKIP  %s%s\n' "${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }" "$reason"
}

# Call at end of every test file.
dnav_test_finish() {
  printf '# dnav-test: pass=%s fail=%s skip=%s\n' \
    "${DNAV_TEST_PASS:-0}" "${DNAV_TEST_FAIL:-0}" "${DNAV_TEST_SKIP:-0}"
  if (( DNAV_TEST_FAIL > 0 )); then
    exit 1
  fi
  exit 0
}
