#!/usr/bin/env bash
# The application quality gate, as a script instead of prose repeated in every agent prompt.
#
#   bash .claude/scripts/check-app.sh [--skip-build] [--update-baseline]
#
# Runs, from NGM_ROOT/app:  npm run build → npm run test → npm run lint
# and compares lint problem counts and the test count against .agent-context/baseline.json.
# Lint does NOT pass cleanly on main, so the gate is "no NEW lint problems", never "lint clean".
#
# Exit 0  = PASS (build ok, tests ok, no new lint problems, no fewer tests than baseline)
# Exit 1  = FAIL (details printed)
# --update-baseline rewrites baseline.json from this run. Orchestrator only, after the user
# has agreed the new numbers are the accepted state of main.

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
ngm="${NGM_ROOT:-$HOME/git/ngm.app}"
[ -f "$proj/app/package.json" ] && ngm="$proj"
baseline="$proj/.agent-context/baseline.json"

skip_build=0; update=0
for a in "$@"; do
  case "$a" in
    --skip-build) skip_build=1 ;;
    --update-baseline) update=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if [ ! -f "$ngm/app/package.json" ]; then
  echo "check-app: cannot find NGM app at $ngm/app (set NGM_ROOT)" >&2; exit 2
fi
if [ ! -f "$baseline" ]; then
  echo "check-app: baseline not found at $baseline" >&2; exit 2
fi

cd "$ngm/app" || exit 2
tmp="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/check-app.$$")"; mkdir -p "$tmp"

read_baseline() { node -e '
  const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  console.log([b.lint.errors, b.lint.warnings, b.tests.count].join(" "));
' "$baseline"; }
read -r b_err b_warn b_tests <<<"$(read_baseline)"

fail=0
# ---- build --------------------------------------------------------------------------------
if [ "$skip_build" -eq 1 ]; then
  build="SKIPPED"
else
  if npm run build >"$tmp/build.log" 2>&1; then build="PASS"; else build="FAIL"; fail=1; fi
fi

# ---- test ---------------------------------------------------------------------------------
if npm run test >"$tmp/test.log" 2>&1; then test_status="PASS"; else test_status="FAIL"; fail=1; fi
# vitest summary line: "      Tests  21 passed (21)"
tests="$(sed -e 's/\x1b\[[0-9;]*m//g' "$tmp/test.log" | grep -E '^\s*Tests\s' | grep -Eo '[0-9]+ passed' | grep -Eo '[0-9]+' | head -1)"
tests="${tests:-0}"
if [ "$tests" -lt "$b_tests" ]; then test_status="FAIL (fewer tests than baseline: $tests < $b_tests)"; fail=1; fi

# ---- lint ---------------------------------------------------------------------------------
npm run lint >"$tmp/lint.log" 2>&1
# eslint summary: "✖ 36 problems (22 errors, 14 warnings)"; absent when clean.
summary="$(sed -e 's/\x1b\[[0-9;]*m//g' "$tmp/lint.log" | grep -E 'problems? \([0-9]+ errors?, [0-9]+ warnings?\)' | tail -1)"
if [ -n "$summary" ]; then
  errs="$(printf '%s' "$summary" | grep -Eo '[0-9]+ errors?' | grep -Eo '[0-9]+')"
  warns="$(printf '%s' "$summary" | grep -Eo '[0-9]+ warnings?' | grep -Eo '[0-9]+')"
else
  errs=0; warns=0
fi
if [ "$errs" -gt "$b_err" ] || [ "$warns" -gt "$b_warn" ]; then
  lint="FAIL (new problems)"; fail=1
elif [ "$errs" -lt "$b_err" ] || [ "$warns" -lt "$b_warn" ]; then
  lint="PASS (fewer than baseline — was this a requested lint fix? if so, update the baseline)"
else
  lint="PASS (no new problems)"
fi

# ---- summary ------------------------------------------------------------------------------
echo "CHECK-APP  build=$build  test=$test_status tests=$tests(baseline $b_tests)  lint=${errs}e/${warns}w (baseline ${b_err}e/${b_warn}w) $lint"
if [ "$fail" -eq 1 ]; then
  echo "--- failing output (tail) ---"
  [ "$build" = "FAIL" ] && { echo "[build]"; tail -40 "$tmp/build.log"; }
  case "$test_status" in FAIL*) echo "[test]"; sed -e 's/\x1b\[[0-9;]*m//g' "$tmp/test.log" | tail -40 ;; esac
  case "$lint" in FAIL*) echo "[lint — compare against baseline to find the NEW ones]"; sed -e 's/\x1b\[[0-9;]*m//g' "$tmp/lint.log" | grep -E '^\s+[0-9]+:[0-9]+' | tail -60 ;; esac
fi

if [ "$update" -eq 1 ] && [ "$build" != "FAIL" ]; then
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const b = JSON.parse(fs.readFileSync(p, "utf8"));
    b.lint = { errors: +process.argv[2], warnings: +process.argv[3] };
    b.tests = { count: +process.argv[4] };
    b.verified = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(p, JSON.stringify(b, null, 2) + "\n");
  ' "$baseline" "$errs" "$warns" "$tests"
  echo "baseline updated: $baseline"
fi

rm -rf "$tmp"
exit "$fail"
