# Assertion helpers for zsh DNav tests (source, do not execute).
# Counters: DNAV_TEST_PASS DNAV_TEST_FAIL DNAV_TEST_SKIP DNAV_TEST_NAME

typeset -gHi DNAV_TEST_PASS=${DNAV_TEST_PASS:-0}
typeset -gHi DNAV_TEST_FAIL=${DNAV_TEST_FAIL:-0}
typeset -gHi DNAV_TEST_SKIP=${DNAV_TEST_SKIP:-0}
typeset -gH DNAV_TEST_NAME=${DNAV_TEST_NAME:-}

_dnav_test_fail() {
  local msg="$1"
  DNAV_TEST_FAIL+=1
  print -ru2 -- "  FAIL  ${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }$msg"
  return 1
}

_dnav_test_pass() {
  local msg="${1:-}"
  DNAV_TEST_PASS+=1
  if [[ -n ${DNAV_TEST_VERBOSE:-} ]]; then
    print -r -- "  ok    ${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }$msg"
  fi
  return 0
}

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-values equal}"
  if [[ $actual == "$expected" ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (expected=${(q)expected} actual=${(q)actual})"
  fi
}

assert_ne() {
  local actual="$1" unexpected="$2" msg="${3:-values differ}"
  if [[ $actual != "$unexpected" ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (both=${(q)actual})"
  fi
}

assert_ok() {
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

assert_fn() {
  if (( $+functions[$1] )); then
    _dnav_test_pass "function $1"
  else
    _dnav_test_fail "missing function: $1"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains}"
  if [[ $haystack == *"$needle"* ]]; then
    _dnav_test_pass "$msg"
  else
    _dnav_test_fail "$msg (missing ${(q)needle})"
  fi
}

assert_file() {
  if [[ -f $1 ]]; then
    _dnav_test_pass "${2:-file exists: $1}"
  else
    _dnav_test_fail "${2:-file missing: $1}"
  fi
}

assert_dir() {
  if [[ -d $1 ]]; then
    _dnav_test_pass "${2:-dir exists: $1}"
  else
    _dnav_test_fail "${2:-dir missing: $1}"
  fi
}

assert_gt() {
  if (( $1 > $2 )); then
    _dnav_test_pass "${3:-$1 > $2}"
  else
    _dnav_test_fail "${3:-$1 > $2} (got $1 <= $2)"
  fi
}

assert_ge() {
  if (( $1 >= $2 )); then
    _dnav_test_pass "${3:-$1 >= $2}"
  else
    _dnav_test_fail "${3:-$1 >= $2} (got $1 < $2)"
  fi
}

run_test() {
  local name="$1"
  DNAV_TEST_NAME="$name"
  if [[ -n ${DNAV_TEST_VERBOSE:-} ]]; then
    print -r -- "  RUN   $name"
  fi
  "$name"
  DNAV_TEST_NAME=""
}

skip_test() {
  local reason="${1:-skipped}"
  DNAV_TEST_SKIP+=1
  print -r -- "  SKIP  ${DNAV_TEST_NAME:+$DNAV_TEST_NAME: }$reason"
}

dnav_test_finish() {
  print -r -- "# dnav-test: pass=$DNAV_TEST_PASS fail=$DNAV_TEST_FAIL skip=$DNAV_TEST_SKIP"
  (( DNAV_TEST_FAIL == 0 ))
}
