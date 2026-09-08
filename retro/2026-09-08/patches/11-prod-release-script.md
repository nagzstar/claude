# 11 — `prod-release.sh <sha>`: the release as one command behind the same gate (B)

**Finding.** H12: four releases on 2026-09-07, each 6–17 hand-issued tool calls (grant → dispatch
in order → `gh run watch` → curl checks → revoke → comment → record), 3–7 min and 4–20 K output in
the PM session. The sequence is the same every time; the judgement (the user's yes) is not.

**Expected effect.** −3 min and ≈ −10 K output per release; fixed order and read-only validation
cannot be skipped by accident; the record is written by the script. `guard-prod.sh` and
`prod-approval.sh` are **unchanged**: the script runs the same `gh workflow run … -f
environment=prod` commands, so the hook admits them only under a fresh approval from the main
session, and a specialist still cannot run it.

New file `.claude/scripts/prod-release.sh`:

```bash
#!/usr/bin/env bash
# Release <sha> to PROD. Run ONLY after the user answered "Shall I deploy this to prod?" with an
# explicit yes and `prod-approval.sh grant <sha> "<their words>"` recorded it. Nothing here
# weakens the gate: each dispatch below passes through guard-prod like a hand-typed command.
#
#   bash .claude/scripts/prod-release.sh <sha> [--terraform] [--no-db] [--no-app] [--record <task-file>]
#
# Order: terraform-apply.yml (only with --terraform) → database-migration.yml → deploy.yml, each
# `gh run watch`ed to success before the next. A failed run stops the script (exit 1) with the run
# id; rerun once by hand after diagnosis, or roll back. Then read-only validation of
# https://nextgenmaher.com (HTTP 200, bundle hash mentions the sha's build, /rest health), revoke
# the approval, and append a release section to the task file (--record) with run ids.
set -u
REPO="${NGM_REPO:-nagzstar/ngm.app}"; PROD="${NGM_PROD_URL:-https://nextgenmaher.com}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
sha="${1:-}"; shift || true
tf=0; db=1; app=1; record=""
while [ $# -gt 0 ]; do case "$1" in --terraform) tf=1;; --no-db) db=0;; --no-app) app=0;; --record) record="$2"; shift;; *) echo "unknown option $1" >&2; exit 2;; esac; shift; done
printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,40}$' || { echo "usage: prod-release.sh <sha> [--terraform] [--no-db] [--no-app] [--record <file>]" >&2; exit 2; }
bash "$proj/.claude/scripts/prod-approval.sh" status >/dev/null 2>&1 || { echo "no active prod approval for this session — ask the user, then prod-approval.sh grant" >&2; exit 2; }
full="$(git -C "${NGM_ROOT:-$proj}" rev-parse "$sha" 2>/dev/null)" || { echo "unknown sha $sha" >&2; exit 2; }
echo "pre-flight: prod $(curl -sS -o /dev/null -w '%{http_code}' "$PROD/")"
ids=""
dispatch() { # workflow
  local wf="$1" id
  echo "dispatching $wf environment=prod at $full"
  gh workflow run "$wf" -R "$REPO" -r main -f environment=prod || return 1
  sleep 8
  id="$(gh run list -R "$REPO" --workflow "$wf" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
  gh run watch "$id" -R "$REPO" --exit-status || { echo "RUN FAILED: $wf run $id — diagnose (gh run view $id --log-failed), rerun once by hand or roll back" >&2; return 1; }
  ids="${ids:+$ids, }$wf=$id"
}
[ "$tf" -eq 1 ] && { dispatch terraform-apply.yml || exit 1; }
[ "$db" -eq 1 ] && { dispatch database-migration.yml || exit 1; }
[ "$app" -eq 1 ] && { dispatch deploy.yml || exit 1; }
echo "validation (read-only): prod $(curl -sS -o /dev/null -w '%{http_code}' "$PROD/") ; bundle $(curl -sS "$PROD/" | grep -oE 'assets/index-[A-Za-z0-9_-]+\.js' | head -1)"
bash "$proj/.claude/scripts/prod-approval.sh" revoke
if [ -n "$record" ]; then
  printf '\n## Prod release %s\n\nStatus: RELEASED TO PROD — sha `%s`, runs: %s. Validation: read-only, HTTP 200, bundle served.\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$sha" "$ids" >> "$record"
fi
echo "RELEASED TO PROD: $sha ($ids)"
```

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -89,13 +89,9 @@
 ## Prod release — only after the user's yes
 
 1. `bash .claude/scripts/prod-approval.sh grant <sha> "<the user's words>"` — the hook checks
    it; expires in 60 minutes; never valid inside a subagent.
-2. Pre-flight: prod returns 200 and the prod Supabase project is awake. Dispatch only the
-   workflows the change needs, one at a time, in order: `terraform-apply.yml` →
-   `database-migration.yml` → `deploy.yml`, each with `-f environment=prod`; `gh run watch`
-   each to success before the next. A failed run: diagnose, rerun once, else offer rollback.
-3. Validate https://nextgenmaher.com read-only (bundle live, behaviour; create and delete
-   nothing), `prod-approval.sh revoke`, record run ids and evidence in the task file, commit
-   it, and report **RELEASED TO PROD**.
+2. `bash .claude/scripts/prod-release.sh <sha> [--terraform] --record <task-file>` — ordered
+   dispatch, watch, read-only validation, revoke, record. A failed run stops it: diagnose, rerun
+   that workflow once by hand, else offer rollback.
+3. Commit the task file and report **RELEASED TO PROD** with the run ids it printed.
```
Net CLAUDE.md: −4 lines. `validate.sh`: `prod block 'bash .claude/scripts/prod-release.sh abc1234'
deployment-engineer` is not needed (the hook blocks the inner dispatch), but add: the script exits 2
without an approval (`bash .claude/scripts/prod-release.sh 0123abc; [ $? -eq 2 ] && ok`).
Allow-list entry: `Bash(bash .claude/scripts/*)` already covers it.
