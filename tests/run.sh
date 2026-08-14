#!/usr/bin/env bash
# Offline test suite for bin/ask. Runs the real script against executable stubs
# on PATH, so it exercises the program rather than asserting over a pure
# argument-building function. No credentials, no network, no vendor spend.
#
#   tests/run.sh          run everything
#   tests/run.sh -v       also print each passing case
#
# A stub records its argv (NUL-delimited, so arguments containing spaces stay
# distinguishable) and its stdin, then exits with the code in STUB_EXIT.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ASK="$HERE/../bin/ask"
VERBOSE="${1:-}"

pass=0
fail=0
failures=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

for v in grok codex claude deepseek; do
  cat > "$BIN/$v" <<'STUB'
#!/usr/bin/env bash
: > "$STUB_OUT.argv"
: > "$STUB_OUT.lens"
# Byte lengths are recorded alongside the arguments because an assertion that
# captures text through $(...) loses trailing newlines and therefore cannot
# tell "newlines preserved" from "newlines stripped" — the exact property some
# of these tests exist to check.
for a in "$@"; do
  printf '%s\0' "$a" >> "$STUB_OUT.argv"
  printf '%s\n' "${#a}" >> "$STUB_OUT.lens"
done
# Deliberately does NOT read stdin. A stub that always drains stdin blocks on
# an idle inherited pipe, which is the very condition one of these tests sets
# up — the stub would hang instead of the assertion failing.
[ -n "${STUB_SLEEP:-}" ] && [ "$STUB_SLEEP" -gt 0 ] && sleep "$STUB_SLEEP"
printf 'stub-stdout\n'
printf 'stub-stderr\n' >&2
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$BIN/$v"
done

export STUB_OUT="$WORK/stub"

# argv_of prints the recorded argv one argument per line, so an assertion can
# match an exact argument rather than a substring of a flattened string.
argv_of() { tr '\0' '\n' < "$STUB_OUT.argv"; }

check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    [ "$VERBOSE" = "-v" ] && printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1))
    failures+=("$1")
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
  return 0
}

run_ask() { PATH="$BIN:$PATH" "$ASK" "$@"; }

echo "bin/ask — offline suite"

# ── argument handling ────────────────────────────────────────────────────────

run_ask grok "hello" >/dev/null 2>&1
check "grok: prompt reaches the child intact" \
  "hello" "$(argv_of | grep -A0 -x 'hello')"

run_ask grok "two words here" >/dev/null 2>&1
check "prompt with spaces stays one argument" \
  "1" "$(argv_of | grep -c -x 'two words here')"

# Extra positional arguments used to be dropped in silence, which turned a
# mistyped command into a quietly different question.
out="$(run_ask grok "first" "second" 2>&1)"; rc=$?
check "extra positional argument is rejected" "2" "$rc"
check "extra positional argument explains itself" \
  "1" "$(printf '%s' "$out" | grep -ci 'unexpected')"

# `--model --resume x` used to parse --resume as the model id.
out="$(run_ask grok --model --resume abc "hi" 2>&1)"; rc=$?
check "option missing its value is rejected" "2" "$rc"

# A prompt starting with - must not be parsed as a flag by the child.
run_ask codex -- "-not-a-flag" >/dev/null 2>&1
check "leading-dash prompt survives as the prompt" \
  "1" "$(argv_of | grep -c -x -- '-not-a-flag')"

# ── stdin ────────────────────────────────────────────────────────────────────

printf 'from stdin' | run_ask grok >/dev/null 2>&1
check "stdin becomes the prompt when no prompt argument is given" \
  "1" "$(argv_of | grep -c -x 'from stdin')"

# 'line1\nline2\n\n' is 13 bytes. Both trailing newlines must survive: a diff
# read from stdin loses its final blank lines otherwise, and only the reader
# knows whether that mattered. Asserted by length because text captured through
# $(...) would have the same newlines stripped again.
printf 'line1\nline2\n\n' | run_ask grok >/dev/null 2>&1
check "stdin keeps its trailing newlines" \
  "13" "$(sed -n '2p' "$STUB_OUT.lens")"

# A redirect from a regular file has no race, so it is folded in automatically.
printf 'DIFFBODY' > "$WORK/diff.txt"
run_ask grok "review this" < "$WORK/diff.txt" >/dev/null 2>&1
check "a file redirect is combined with the prompt, not dropped" \
  "1" "$(argv_of | grep -c 'DIFFBODY')"
check "the prompt survives alongside redirected input" \
  "1" "$(argv_of | grep -c 'review this')"

# A pipe can race a fast writer, so combining from one is opt-in via a final -.
printf 'PIPEBODY' | run_ask grok "review this" - >/dev/null 2>&1
check "an explicit - folds piped input into the prompt" \
  "1" "$(argv_of | grep -c 'PIPEBODY')"

# Without the marker an idle inherited stdin must not be read at all; reading it
# blocked forever whenever one agent invoked another non-interactively.
( sleep 2 ) | run_ask grok "no stdin wanted" >/dev/null 2>&1
check "an idle inherited stdin is ignored rather than blocking" \
  "1" "$(argv_of | grep -c -x 'no stdin wanted')"

# ── exit status and streams ──────────────────────────────────────────────────

STUB_EXIT=7 run_ask grok "x" >/dev/null 2>&1
check "child exit status is passed through" "7" "$?"

out="$(run_ask grok "x" 2>/dev/null)"
check "child stdout reaches stdout" "stub-stdout" "$out"

err="$(run_ask grok "x" 2>&1 >/dev/null)"
check "child stderr stays on stderr" "stub-stderr" "$err"

# ── vendor-specific ──────────────────────────────────────────────────────────

run_ask grok "x" >/dev/null 2>&1
check "grok gets its unattended-approval flag" \
  "1" "$(argv_of | grep -c -x -- '--always-approve')"

run_ask codex "x" >/dev/null 2>&1
check "codex gets the outside-a-repo escape" \
  "1" "$(argv_of | grep -c -x -- '--skip-git-repo-check')"

run_ask grok --model m1 "x" >/dev/null 2>&1
check "model is pinned when asked" "1" "$(argv_of | grep -c -x 'm1')"

run_ask grok "x" >/dev/null 2>&1
check "no model flag when not asked" "0" "$(argv_of | grep -c -x -- '--model')"

# --resume was parsed and then dropped for deepseek, silently starting a fresh
# conversation — the exact failure the guidance warns about.
out="$(run_ask deepseek --resume abc "x" 2>&1)"; rc=$?
check "a resume that cannot be honoured is refused, not ignored" "2" "$rc"

# ── timeout ──────────────────────────────────────────────────────────────────
# A hung child and a thinking child look identical from outside, so the deadline
# is the only thing that tells them apart. STUB_SLEEP makes the stub hang.

start=$(date +%s)
STUB_SLEEP=30 run_ask grok --timeout 2 "x" >/dev/null 2>&1; rc=$?
elapsed=$(( $(date +%s) - start ))
check "a hung child is killed at the deadline" "124" "$rc"
check "the deadline is actually enforced, not merely documented" \
  "yes" "$([ "$elapsed" -lt 15 ] && echo yes || echo "no (${elapsed}s)")"

STUB_SLEEP=0 run_ask grok --timeout 30 "x" >/dev/null 2>&1
check "a child that finishes in time is not disturbed" "0" "$?"

STUB_EXIT=5 run_ask grok --timeout 30 "x" >/dev/null 2>&1
check "exit status survives the timeout wrapper" "5" "$?"

out="$(run_ask grok --timeout abc "x" 2>&1)"; rc=$?
check "a non-numeric timeout is refused" "2" "$rc"

# ── --list ───────────────────────────────────────────────────────────────────

out="$(run_ask --list 2>/dev/null)"
check "--list reports every vendor" "4" "$(printf '%s\n' "$out" | grep -c .)"

# A failing probe used to abort the whole listing under set -e -o pipefail,
# leaving no output at all in exactly the case a user runs --list to diagnose.
out="$(STUB_EXIT=1 run_ask --list 2>/dev/null)"; rc=$?
check "--list survives a failing probe" "0" "$rc"
check "--list still lists every vendor when a probe fails" \
  "4" "$(printf '%s\n' "$out" | grep -c .)"

# ── missing vendor ───────────────────────────────────────────────────────────

rc=0; PATH="$WORK/empty:/usr/bin:/bin" "$ASK" grok "x" >/dev/null 2>&1 || rc=$?
check "a missing CLI exits 3" "3" "$rc"

run_ask nosuchvendor "x" >/dev/null 2>&1
check "an unknown vendor exits 2" "2" "$?"

# ── report ───────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
  printf '%d passed\n' "$pass"
  exit 0
fi
printf '%d passed, %d failed:\n' "$pass" "$fail"
printf '  - %s\n' "${failures[@]}"
exit 1
