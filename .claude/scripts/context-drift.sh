#!/usr/bin/env bash
# Cheap, deterministic drift check for the context files. Run at the start of a session
# (Orchestrator boot) or before trusting project.md / security-model.md / delivery.md.
#
#   bash .claude/scripts/context-drift.sh
#
# Prints the repo areas that changed since each context file's "Last verified" date, and
# the current inventory (migrations, edge functions, workflows, tests) so stale counts in
# prose are obvious. Exit 0 always — this informs, it does not gate.

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
ngm="${NGM_ROOT:-$HOME/git/ngm.app}"
[ -f "$proj/app/package.json" ] && ngm="$proj"
ctx="$proj/.agent-context"

echo "NGM_ROOT: $ngm"
echo "Inventory:"
echo "  migrations:     $(ls "$ngm/supabase/migrations"/*.sql 2>/dev/null | wc -l | tr -d ' ')  (latest: $(ls "$ngm/supabase/migrations" 2>/dev/null | sort | tail -1))"
echo "  edge functions: $(ls -d "$ngm/supabase/functions"/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
echo "  workflows:      $(ls "$ngm/.github/workflows" 2>/dev/null | tr '\n' ' ')"
echo "  test files:     $(find "$ngm/app/src" -name '*.test.*' 2>/dev/null | wc -l | tr -d ' ')"
echo "  shadcn ui:      $(ls "$ngm/app/src/components/ui" 2>/dev/null | wc -l | tr -d ' ') components"
echo "  uncommitted:    $(git -C "$ngm" status --porcelain 2>/dev/null | wc -l | tr -d ' ') paths"
echo

check() {
  local file="$1"; shift
  local date
  date="$(grep -Eo 'Last verified: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$ctx/$file" 2>/dev/null | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  if [ -z "$date" ]; then echo "$file: no 'Last verified' date"; return; fi
  local changed
  changed="$(git -C "$ngm" log --since="$date" --name-only --pretty=format: -- "$@" 2>/dev/null | sort -u | grep -v '^$')"
  local dirty
  dirty="$(git -C "$ngm" status --porcelain -- "$@" 2>/dev/null | awk '{print $2}')"
  if [ -z "$changed" ] && [ -z "$dirty" ]; then
    echo "$file: verified $date — no changes in its sources since"
  else
    echo "$file: verified $date — sources changed since (re-verify before trusting):"
    printf '%s\n%s\n' "$changed" "$dirty" | grep -v '^$' | sort -u | sed 's/^/    /'
  fi
}

check project.md app/package.json app/src/contexts app/src/types app/src/App.tsx supabase terraform .github/workflows
check security-model.md supabase/migrations supabase/functions
check delivery.md .github/workflows terraform

echo
b="$ctx/baseline.json"
[ -f "$b" ] && echo "baseline.json: $(node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(`lint ${b.lint.errors}e/${b.lint.warnings}w, tests ${b.tests.count}, verified ${b.verified}`)' "$b")"
exit 0
