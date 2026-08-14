#!/usr/bin/env bash
# DNav test runner — zero external deps (bash 4+ / zsh / optional pwsh).
#
# Usage:
#   ./tests/run.sh              # bash + zsh (default)
#   ./tests/run.sh --bash       # bash only
#   ./tests/run.sh --zsh        # zsh only
#   ./tests/run.sh --powershell # PowerShell suite (skip if no pwsh)
#   ./tests/run.sh --all        # bash + zsh + powershell
#   ./tests/run.sh -v           # verbose
#   ./tests/run.sh dsearch      # filter by filename
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ROOT"

# Default: both Unix shells (zsh is the primary product surface)
DO_BASH=1
DO_ZSH=1
DO_PS=0
VERBOSE=0
FILTERS=()

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --bash) DO_BASH=1; DO_ZSH=0; DO_PS=0; shift ;;
    --zsh) DO_BASH=0; DO_ZSH=1; DO_PS=0; shift ;;
    --powershell|--ps) DO_BASH=0; DO_ZSH=0; DO_PS=1; shift ;;
    --all) DO_BASH=1; DO_ZSH=1; DO_PS=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    --) shift; FILTERS+=("$@"); break ;;
    -*)
      printf 'unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      FILTERS+=("$1"); shift ;;
  esac
done

export DNAV_TEST_VERBOSE="${DNAV_TEST_VERBOSE:-}"
(( VERBOSE )) && DNAV_TEST_VERBOSE=1 && export DNAV_TEST_VERBOSE

PASS=0
FAIL=0
SKIP=0
FILES_RUN=0
FILES_FAIL=0

run_one() {
  local script="$1" shell="$2"
  local out rc=0
  FILES_RUN=$((FILES_RUN + 1))
  printf '\n==> %s (%s)\n' "${script#$ROOT/}" "$shell"
  set +e
  out="$(DNAV_TEST_VERBOSE="${DNAV_TEST_VERBOSE:-}" "$shell" "$script" 2>&1)"
  rc=$?
  set -e
  if [[ -n $out ]]; then
    printf '%s\n' "$out"
  fi
  local p f s
  p=$(printf '%s\n' "$out" | sed -n 's/^# dnav-test: pass=\([0-9]*\) fail=\([0-9]*\) skip=\([0-9]*\).*/\1/p' | tail -1)
  f=$(printf '%s\n' "$out" | sed -n 's/^# dnav-test: pass=\([0-9]*\) fail=\([0-9]*\) skip=\([0-9]*\).*/\2/p' | tail -1)
  s=$(printf '%s\n' "$out" | sed -n 's/^# dnav-test: pass=\([0-9]*\) fail=\([0-9]*\) skip=\([0-9]*\).*/\3/p' | tail -1)
  if [[ -n $p ]]; then
    PASS=$((PASS + p))
    FAIL=$((FAIL + f))
    SKIP=$((SKIP + ${s:-0}))
  fi
  if (( rc != 0 )); then
    FILES_FAIL=$((FILES_FAIL + 1))
    if [[ -z $p ]]; then
      FAIL=$((FAIL + 1))
    fi
    printf '  ** file exit %s\n' "$rc" >&2
  fi
}

list_scripts() {
  local dir="$1"
  local ext="${2:-sh}"
  local f
  shopt -s nullglob
  if ((${#FILTERS[@]})); then
    local filt
    for filt in "${FILTERS[@]}"; do
      if [[ -f $filt ]]; then
        printf '%s\n' "$(cd -- "$(dirname -- "$filt")" && pwd)/$(basename -- "$filt")"
      elif [[ -f $ROOT/$filt ]]; then
        printf '%s\n' "$ROOT/$filt"
      elif [[ -f $ROOT/tests/$filt ]]; then
        printf '%s\n' "$ROOT/tests/$filt"
      elif [[ -f $dir/$filt ]]; then
        printf '%s\n' "$dir/$filt"
      else
        for f in "$dir"/*."$ext" "$dir"/*.sh "$dir"/*.ps1; do
          [[ -f $f ]] || continue
          [[ $(basename "$f") == *"$filt"* || $f == *"$filt"* ]] && printf '%s\n' "$f"
        done
      fi
    done
  else
    for f in "$dir"/*."$ext"; do
      [[ -f $f ]] && printf '%s\n' "$f"
    done
  fi
  shopt -u nullglob
}

printf 'DNav tests  (repo: %s)\n' "$ROOT"
printf 'bash %s\n' "$(bash --version | head -1)"
if command -v zsh >/dev/null 2>&1; then
  printf 'zsh %s\n' "$(zsh --version 2>/dev/null | head -1)"
fi

if (( DO_BASH )); then
  printf '\n--- bash suite ---\n'
  while IFS= read -r script; do
    [[ -z $script ]] && continue
    run_one "$script" bash
  done < <(list_scripts "$ROOT/tests/bash" sh | sort -u)
fi

if (( DO_ZSH )); then
  if command -v zsh >/dev/null 2>&1; then
    printf '\n--- zsh suite ---\n'
    while IFS= read -r script; do
      [[ -z $script ]] && continue
      run_one "$script" zsh
    done < <(list_scripts "$ROOT/tests/zsh" zsh | sort -u)
  else
    printf '\n--- zsh suite SKIPPED (zsh not installed) ---\n'
    SKIP=$((SKIP + 1))
  fi
fi

if (( DO_PS )); then
  printf '\n--- powershell suite ---\n'
  if command -v pwsh >/dev/null 2>&1; then
    set +e
    local_ps_out=
    if (( VERBOSE )); then
      local_ps_out="$(pwsh -NoProfile -File "$ROOT/tests/run.ps1" -VerboseTests 2>&1)"
    else
      local_ps_out="$(pwsh -NoProfile -File "$ROOT/tests/run.ps1" 2>&1)"
    fi
    local_ps_rc=$?
    set -e
    printf '%s\n' "$local_ps_out"
    p=$(printf '%s\n' "$local_ps_out" | sed -n 's/.*Assertions: pass=\([0-9]*\)  fail=\([0-9]*\)  skip=\([0-9]*\).*/\1/p' | tail -1)
    f=$(printf '%s\n' "$local_ps_out" | sed -n 's/.*Assertions: pass=\([0-9]*\)  fail=\([0-9]*\)  skip=\([0-9]*\).*/\2/p' | tail -1)
    s=$(printf '%s\n' "$local_ps_out" | sed -n 's/.*Assertions: pass=\([0-9]*\)  fail=\([0-9]*\)  skip=\([0-9]*\).*/\3/p' | tail -1)
    # Also sum per-file counters if summary line missing
    if [[ -z $p ]]; then
      while IFS= read -r line; do
        if [[ $line =~ pass=([0-9]+)\ fail=([0-9]+)\ skip=([0-9]+) ]]; then
          PASS=$((PASS + BASH_REMATCH[1]))
          FAIL=$((FAIL + BASH_REMATCH[2]))
          SKIP=$((SKIP + BASH_REMATCH[3]))
        fi
      done <<< "$local_ps_out"
    else
      PASS=$((PASS + p))
      FAIL=$((FAIL + f))
      SKIP=$((SKIP + ${s:-0}))
    fi
    FILES_RUN=$((FILES_RUN + 1))
    if (( local_ps_rc != 0 )); then
      FILES_FAIL=$((FILES_FAIL + 1))
    fi
  else
    printf '  SKIP  pwsh not installed (PowerShell suite reserved for Windows/CI)\n'
    printf '  see tests/powershell/README.md\n'
    SKIP=$((SKIP + 1))
  fi
fi

printf '\n========================================\n'
printf 'Files: %d  failed-files: %d\n' "$FILES_RUN" "$FILES_FAIL"
printf 'Assertions: pass=%d  fail=%d  skip=%d\n' "$PASS" "$FAIL" "$SKIP"
printf '========================================\n'

if (( FAIL > 0 || FILES_FAIL > 0 )); then
  exit 1
fi
exit 0
